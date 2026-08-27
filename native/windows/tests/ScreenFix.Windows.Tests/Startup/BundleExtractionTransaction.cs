using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace ScreenFix.Windows.Tests.Startup;

internal interface IBundleExtractionFileSystem
{
    FileAttributes GetAttributes(string path);

    void CreateDirectory(string path);

    Stream CreateIdentityFile(string path, byte[] identity);

    byte[] ReadIdentityFile(string path);

    IEnumerable<string> EnumerateEntries(string path);

    void DeleteDirectory(string path);
}

internal interface IBundleExtractionDeletionAdapter
{
    IBundleExtractionRootAnchor CreateAnchor(string rootPath);
}

internal interface IBundleExtractionRootAnchor : IDisposable
{
    void VerifyOwnedPath(string path);

    void DeleteOwnedRoot(
        string rootPath,
        Action<string> validateOwnedRoot,
        Action releaseIdentityAnchor);
}

internal sealed record BundleExtractionTransactionDependencies(
    IBundleExtractionFileSystem FileSystem,
    Func<string, string> CreateRootPath,
    Func<byte[]> CreateIdentity,
    IBundleExtractionDeletionAdapter DeletionAdapter)
{
    internal static BundleExtractionTransactionDependencies Production() =>
        new(
            new SystemBundleExtractionFileSystem(),
            runnerTemp => Path.Combine(
                runnerTemp,
                "screenfix-bundle-extraction-" + Guid.NewGuid().ToString("N")),
            () => RandomNumberGenerator.GetBytes(32),
            new WindowsBundleExtractionDeletionAdapter());
}

internal sealed class BundleExtractionTransaction : IDisposable
{
    private const string IdentityFileName = ".screenfix-extraction-owner";

    private readonly BundleExtractionTransactionDependencies dependencies;
    private readonly string runnerTemp;
    private readonly string identityPath;
    private readonly byte[] identity;
    private readonly HashSet<string> children = new(StringComparer.OrdinalIgnoreCase);
    private Stream? identityHandle;
    private IBundleExtractionRootAnchor? rootAnchor;
    private Exception? recoveryFailure;
    private int unprovenChildren;
    private bool disposed;

    internal BundleExtractionTransaction(
        bool allowDisposableAccountMutation,
        string runnerTemp)
        : this(
            allowDisposableAccountMutation,
            runnerTemp,
            BundleExtractionTransactionDependencies.Production())
    {
    }

    internal BundleExtractionTransaction(
        bool allowDisposableAccountMutation,
        string runnerTemp,
        BundleExtractionTransactionDependencies dependencies)
    {
        ArgumentNullException.ThrowIfNull(dependencies);
        if (!allowDisposableAccountMutation)
        {
            throw new InvalidOperationException(
                "Bundle extraction requires explicit disposable-account opt-in.");
        }

        this.dependencies = dependencies;
        this.runnerTemp = ValidateRunnerTemp(runnerTemp, dependencies);

        RootPath = NormalizeAbsoluteNonRoot(
            dependencies.CreateRootPath(this.runnerTemp),
            "bundle extraction root");
        RequireStrictChild(this.runnerTemp, RootPath);
        ValidateCandidateIsAbsent(RootPath);
        ValidateExistingAncestors(Path.GetDirectoryName(RootPath)!);

        dependencies.FileSystem.CreateDirectory(RootPath);
        try
        {
            ValidateDirectory(RootPath);
            rootAnchor = dependencies.DeletionAdapter.CreateAnchor(RootPath);
            identity = dependencies.CreateIdentity();
            if (identity.Length == 0)
            {
                throw new InvalidOperationException("Bundle extraction identity must not be empty.");
            }

            identityPath = Path.Combine(RootPath, IdentityFileName);
            identityHandle = dependencies.FileSystem.CreateIdentityFile(identityPath, identity);
            ValidateOwnedRoot(RootPath);
        }
        catch (Exception error)
        {
            PreserveUnprovenRootAfterFailure(error);
            throw;
        }
    }

    internal string RootPath { get; }

    internal static string ValidateRunnerTemp(string runnerTemp) =>
        ValidateRunnerTemp(
            runnerTemp,
            BundleExtractionTransactionDependencies.Production());

    private static string ValidateRunnerTemp(
        string runnerTemp,
        BundleExtractionTransactionDependencies dependencies)
    {
        var fullPath = NormalizeAbsoluteNonRoot(runnerTemp, "RUNNER_TEMP");
        FileAttributes attributes;
        try
        {
            attributes = dependencies.FileSystem.GetAttributes(fullPath);
        }
        catch (Exception error) when (
            error is FileNotFoundException or DirectoryNotFoundException)
        {
            throw new InvalidOperationException($"RUNNER_TEMP must exist: {fullPath}.");
        }

        ValidateRunnerTempAttributes(fullPath, attributes);
        var current = Path.GetDirectoryName(fullPath);
        while (current is not null)
        {
            ValidateRunnerTempAttributes(
                current,
                dependencies.FileSystem.GetAttributes(current));
            var parent = Path.GetDirectoryName(current);
            if (parent is null || parent == current)
            {
                break;
            }

            current = parent;
        }

        return fullPath;
    }

    private static void ValidateRunnerTempAttributes(
        string path,
        FileAttributes attributes)
    {
        if ((attributes & FileAttributes.ReparsePoint) != 0)
        {
            throw new InvalidOperationException(
                $"Bundle extraction path must not be a reparse point: {path}.");
        }

        if ((attributes & FileAttributes.Directory) == 0)
        {
            throw new InvalidOperationException(
                $"Bundle extraction ancestor must be a directory: {path}.");
        }
    }

    internal string CreateFirstExtractionPath(string variant, int sampleIndex)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        ValidateVariant(variant);
        if (sampleIndex is < 0 or >= 5)
        {
            throw new ArgumentOutOfRangeException(nameof(sampleIndex));
        }

        return CreateChild($"first-{variant}-{sampleIndex + 1}");
    }

    internal string CreateWarmExtractionPath(string variant)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        ValidateVariant(variant);
        return CreateChild($"warm-{variant}");
    }

    internal void RecordChildStarted()
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        checked
        {
            unprovenChildren++;
        }
    }

    internal void RecordChildExitProven()
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        if (unprovenChildren == 0)
        {
            throw new InvalidOperationException("No unproven exact child is registered.");
        }

        unprovenChildren--;
    }

    internal void RecordRecoveryFailure(Exception error)
    {
        ArgumentNullException.ThrowIfNull(error);
        ObjectDisposedException.ThrowIf(disposed, this);
        if (unprovenChildren == 0)
        {
            throw new InvalidOperationException(
                "A recovery failure requires an unproven exact child.");
        }

        recoveryFailure ??= error;
    }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }

        disposed = true;
        if (unprovenChildren != 0)
        {
            ReleaseIdentityHandle();
            ReleaseRootAnchor();
            throw new InvalidOperationException(
                $"Exact-child exit was not proven; retained extraction root: {RootPath}.",
                recoveryFailure);
        }

        try
        {
            ValidateOwnedRoot(RootPath);
        }
        catch (Exception error)
        {
            ReleaseIdentityHandle();
            ReleaseRootAnchor();
            throw new InvalidOperationException(
                $"Bundle extraction root changed; retained extraction root: {RootPath}.",
                error);
        }

        try
        {
            var ownedAnchor = rootAnchor
                ?? throw new InvalidOperationException(
                    "Bundle extraction root ownership anchor is unavailable.");
            ownedAnchor.DeleteOwnedRoot(
                RootPath,
                ValidateOwnedRoot,
                ReleaseIdentityHandle);
            ReleaseRootAnchor();
            if (TryGetAttributes(RootPath, out _))
            {
                throw new IOException(
                    "A path exists at the original extraction root after owned cleanup.");
            }
        }
        catch (Exception error)
        {
            ReleaseIdentityHandle();
            ReleaseRootAnchor();
            throw new InvalidOperationException(
                "Bundle extraction cleanup failed; owned recovery retained for " +
                $"original root: {RootPath}.",
                error);
        }
    }

    private string CreateChild(string name)
    {
        ValidateOwnedRoot(RootPath);
        var child = Path.GetFullPath(Path.Combine(RootPath, name));
        RequireStrictChild(RootPath, child);
        if (!children.Add(child))
        {
            throw new InvalidOperationException(
                $"Bundle extraction child was already created: {child}.");
        }

        ValidateCandidateIsAbsent(child);
        dependencies.FileSystem.CreateDirectory(child);
        ValidateDirectory(child);
        return child;
    }

    private void ValidateOwnedRoot(string rootPath)
    {
        RequireStrictChild(runnerTemp, rootPath);
        ValidateExistingAncestors(rootPath);
        ValidateDirectory(rootPath);
        var ownedAnchor = rootAnchor
            ?? throw new InvalidOperationException(
                "Bundle extraction root ownership anchor is unavailable.");
        ownedAnchor.VerifyOwnedPath(rootPath);
        var actualIdentity = dependencies.FileSystem.ReadIdentityFile(
            Path.Combine(rootPath, IdentityFileName));
        if (!actualIdentity.AsSpan().SequenceEqual(identity))
        {
            throw new IOException("Bundle extraction root identity changed.");
        }

        ValidateOwnedTree(rootPath);
    }

    private void ValidateOwnedTree(string rootPath)
    {
        var pending = new Stack<string>();
        pending.Push(rootPath);
        while (pending.Count > 0)
        {
            foreach (var entry in dependencies.FileSystem.EnumerateEntries(pending.Pop()))
            {
                var attributes = dependencies.FileSystem.GetAttributes(entry);
                if ((attributes & FileAttributes.ReparsePoint) != 0)
                {
                    throw new IOException(
                        $"Bundle extraction entry is a reparse point: {entry}.");
                }

                if ((attributes & FileAttributes.Directory) != 0)
                {
                    pending.Push(entry);
                }
            }
        }
    }

    private void ValidateCandidateIsAbsent(string path)
    {
        if (!TryGetAttributes(path, out var attributes))
        {
            return;
        }

        if ((attributes & FileAttributes.ReparsePoint) != 0)
        {
            throw new InvalidOperationException(
                $"Bundle extraction path must not be a reparse point: {path}.");
        }

        throw new InvalidOperationException(
            $"Bundle extraction root must be initially absent: {path}.");
    }

    private void ValidateDirectory(string path)
    {
        var attributes = dependencies.FileSystem.GetAttributes(path);
        if ((attributes & FileAttributes.ReparsePoint) != 0)
        {
            throw new InvalidOperationException(
                $"Bundle extraction path must not be a reparse point: {path}.");
        }

        if ((attributes & FileAttributes.Directory) == 0)
        {
            throw new InvalidOperationException(
                $"Bundle extraction ancestor must be a directory: {path}.");
        }
    }

    private void ValidateExistingAncestors(string path)
    {
        var current = path;
        while (true)
        {
            if (TryGetAttributes(current, out var attributes))
            {
                if ((attributes & FileAttributes.ReparsePoint) != 0)
                {
                    throw new InvalidOperationException(
                        $"Bundle extraction path must not be a reparse point: {current}.");
                }

                if ((attributes & FileAttributes.Directory) == 0)
                {
                    throw new InvalidOperationException(
                        $"Bundle extraction ancestor must be a directory: {current}.");
                }
            }

            var parent = Path.GetDirectoryName(current);
            if (parent is null || parent == current)
            {
                return;
            }

            current = parent;
        }
    }

    private bool TryGetAttributes(string path, out FileAttributes attributes)
    {
        try
        {
            attributes = dependencies.FileSystem.GetAttributes(path);
            return true;
        }
        catch (FileNotFoundException)
        {
            attributes = default;
            return false;
        }
        catch (DirectoryNotFoundException)
        {
            attributes = default;
            return false;
        }
    }

    private static string NormalizeAbsoluteNonRoot(string path, string description)
    {
        if (string.IsNullOrWhiteSpace(path) || !Path.IsPathFullyQualified(path))
        {
            throw new InvalidOperationException($"{description} must be absolute.");
        }

        var fullPath = Path.GetFullPath(path);
        var root = Path.GetPathRoot(fullPath);
        if (string.IsNullOrWhiteSpace(root)
            || Path.TrimEndingDirectorySeparator(fullPath).Equals(
                Path.TrimEndingDirectorySeparator(root),
                StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException($"{description} must not be a filesystem root.");
        }

        return fullPath;
    }

    private static void RequireStrictChild(string root, string candidate)
    {
        var relative = Path.GetRelativePath(root, candidate);
        if (relative == "."
            || Path.IsPathFullyQualified(relative)
            || relative == ".."
            || relative.StartsWith(".." + Path.DirectorySeparatorChar, StringComparison.Ordinal)
            || relative.StartsWith(".." + Path.AltDirectorySeparatorChar, StringComparison.Ordinal))
        {
            throw new InvalidOperationException(
                "Bundle extraction root must be a strict child of RUNNER_TEMP.");
        }
    }

    private static void ValidateVariant(string variant)
    {
        if (variant is not ("compressed" or "uncompressed"))
        {
            throw new ArgumentOutOfRangeException(nameof(variant));
        }
    }

    private void ReleaseIdentityHandle()
    {
        identityHandle?.Dispose();
        identityHandle = null;
    }

    private void ReleaseRootAnchor()
    {
        rootAnchor?.Dispose();
        rootAnchor = null;
    }

    private void PreserveUnprovenRootAfterFailure(Exception initializationError)
    {
        ReleaseIdentityHandle();
        ReleaseRootAnchor();
        if (TryGetAttributes(RootPath, out _))
        {
            throw new InvalidOperationException(
                $"Bundle extraction initialization failed; retained extraction root: {RootPath}.",
                initializationError);
        }
    }

}

internal sealed class SystemBundleExtractionFileSystem : IBundleExtractionFileSystem
{
    public FileAttributes GetAttributes(string path) => File.GetAttributes(path);

    public void CreateDirectory(string path) => Directory.CreateDirectory(path);

    public Stream CreateIdentityFile(string path, byte[] identity)
    {
        using (var writer = new FileStream(
                   path,
                   FileMode.CreateNew,
                   FileAccess.Write,
                   FileShare.None))
        {
            writer.Write(identity);
            writer.Flush(flushToDisk: true);
        }

        return new FileStream(
            path,
            FileMode.Open,
            FileAccess.Read,
            FileShare.Read | FileShare.Delete);
    }

    public byte[] ReadIdentityFile(string path)
    {
        using var stream = new FileStream(
            path,
            FileMode.Open,
            FileAccess.Read,
            FileShare.ReadWrite | FileShare.Delete);
        using var content = new MemoryStream();
        stream.CopyTo(content);
        return content.ToArray();
    }

    public IEnumerable<string> EnumerateEntries(string path) =>
        Directory.EnumerateFileSystemEntries(path);

    public void DeleteDirectory(string path) => Directory.Delete(path, recursive: true);
}

internal sealed class WindowsBundleExtractionDeletionAdapter : IBundleExtractionDeletionAdapter
{
    public IBundleExtractionRootAnchor CreateAnchor(string rootPath)
    {
        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException(
                "The production bundle-extraction deletion anchor requires Windows.");
        }

        return WindowsBundleExtractionRootAnchor.Create(rootPath);
    }
}

internal sealed class WindowsBundleExtractionRootAnchor : IBundleExtractionRootAnchor
{
    private const uint DeleteAccess = 0x00010000;
    private const uint FileReadAttributes = 0x00000080;
    private const uint FileShareRead = 0x00000001;
    private const uint FileShareWrite = 0x00000002;
    private const uint FileShareDelete = 0x00000004;
    private const uint OpenExisting = 3;
    private const uint FileFlagBackupSemantics = 0x02000000;
    private const uint FileFlagOpenReparsePoint = 0x00200000;
    private const int FileDispositionInfoClass = 4;
    private const int FileAttributeTagInfoClass = 9;
    private const int FileIdInfoClass = 18;

    private SafeFileHandle? ownedHandle;
    private readonly FileIdentity identity;

    private WindowsBundleExtractionRootAnchor(
        SafeFileHandle ownedHandle,
        FileIdentity identity)
    {
        this.ownedHandle = ownedHandle;
        this.identity = identity;
    }

    internal static WindowsBundleExtractionRootAnchor Create(string rootPath)
    {
        var handle = OpenDirectory(
            rootPath,
            FileReadAttributes,
            FileShareRead | FileShareWrite | FileShareDelete);
        try
        {
            return new WindowsBundleExtractionRootAnchor(handle, ReadIdentity(handle));
        }
        catch
        {
            handle.Dispose();
            throw;
        }
    }

    public void DeleteOwnedRoot(
        string rootPath,
        Action<string> validateOwnedRoot,
        Action releaseIdentityAnchor)
    {
        ObjectDisposedException.ThrowIf(ownedHandle is null, this);
        var quarantine = CreateQuarantinePath(rootPath);
        SafeFileHandle? lockedQuarantine = null;
        try
        {
            releaseIdentityAnchor();
            Directory.Move(rootPath, quarantine);
            lockedQuarantine = OpenDirectory(
                quarantine,
                FileReadAttributes | DeleteAccess,
                FileShareRead | FileShareWrite);
            var handedOffIdentity = ReadIdentity(lockedQuarantine);
            if (handedOffIdentity != identity)
            {
                throw new IOException(
                    "Owned extraction directory changed during final handoff. " +
                    $"Owned recovery path: {CurrentOwnedPath()}. " +
                    $"Replacement quarantine: {quarantine}.");
            }

            validateOwnedRoot(quarantine);
            DeleteContents(quarantine);
            MarkDeleteOnClose(lockedQuarantine);
            ReleaseOwnedHandle();
            lockedQuarantine.Dispose();
            lockedQuarantine = null;

            if (PathEntryExists(quarantine))
            {
                throw new IOException(
                    $"Owned extraction quarantine still exists after handle deletion: {quarantine}.");
            }
        }
        catch (Exception error)
        {
            throw new IOException(
                "Owned extraction deletion handoff failed. " +
                $"Owned recovery path: {CurrentOwnedPath()}. " +
                $"Quarantine path: {quarantine}.",
                error);
        }
        finally
        {
            lockedQuarantine?.Dispose();
        }
    }

    public void VerifyOwnedPath(string path)
    {
        ObjectDisposedException.ThrowIf(ownedHandle is null, this);
        using var candidate = OpenDirectory(
            path,
            FileReadAttributes,
            FileShareRead | FileShareWrite | FileShareDelete);
        if (ReadIdentity(candidate) != identity)
        {
            throw new IOException(
                $"Extraction path does not reference the anchored directory: {path}.");
        }
    }

    public void Dispose() => ReleaseOwnedHandle();

    private static string CreateQuarantinePath(string rootPath)
    {
        var parent = Path.GetDirectoryName(rootPath)
            ?? throw new IOException("Owned extraction root has no parent directory.");
        var quarantine = Path.Combine(
            parent,
            ".screenfix-delete-" + Guid.NewGuid().ToString("N"));
        if (PathEntryExists(quarantine))
        {
            throw new IOException(
                $"Owned extraction quarantine must be initially absent: {quarantine}.");
        }

        return quarantine;
    }

    private static void DeleteContents(string rootPath)
    {
        foreach (var entry in Directory.EnumerateFileSystemEntries(rootPath).ToArray())
        {
            var attributes = File.GetAttributes(entry);
            if ((attributes & FileAttributes.ReparsePoint) != 0)
            {
                throw new IOException(
                    $"Owned extraction quarantine entry is a reparse point: {entry}.");
            }

            if ((attributes & FileAttributes.Directory) != 0)
            {
                Directory.Delete(entry, recursive: true);
            }
            else
            {
                File.Delete(entry);
            }
        }
    }

    private string CurrentOwnedPath()
    {
        var handle = ownedHandle;
        if (handle is null || handle.IsInvalid || handle.IsClosed)
        {
            return "<ownership anchor released>";
        }

        var path = new StringBuilder(32_768);
        var length = GetFinalPathNameByHandleW(handle, path, path.Capacity, 0);
        return length is > 0 and < 32_768
            ? path.ToString()
            : "<owned path unavailable>";
    }

    private void ReleaseOwnedHandle()
    {
        ownedHandle?.Dispose();
        ownedHandle = null;
    }

    private static SafeFileHandle OpenDirectory(
        string path,
        uint desiredAccess,
        uint shareMode)
    {
        var handle = CreateFileW(
            path,
            desiredAccess,
            shareMode,
            IntPtr.Zero,
            OpenExisting,
            FileFlagBackupSemantics | FileFlagOpenReparsePoint,
            IntPtr.Zero);
        if (handle.IsInvalid)
        {
            var error = new Win32Exception(Marshal.GetLastWin32Error());
            handle.Dispose();
            throw new IOException($"Could not anchor extraction directory: {path}.", error);
        }


        if (!GetFileInformationByHandleEx(
                handle,
                FileAttributeTagInfoClass,
                out FileAttributeTagInformation attributes,
                Marshal.SizeOf<FileAttributeTagInformation>()))
        {
            var error = new Win32Exception(Marshal.GetLastWin32Error());
            handle.Dispose();
            throw new IOException($"Could not inspect anchored extraction directory: {path}.", error);
        }

        if ((attributes.FileAttributes & (uint)FileAttributes.Directory) == 0
            || (attributes.FileAttributes & (uint)FileAttributes.ReparsePoint) != 0)
        {
            handle.Dispose();
            throw new IOException(
                $"Anchored extraction path must be a non-reparse directory: {path}.");
        }

        return handle;
    }

    private static FileIdentity ReadIdentity(SafeFileHandle handle)
    {
        if (!GetFileInformationByHandleEx(
                handle,
                FileIdInfoClass,
                out FileIdInformation information,
                Marshal.SizeOf<FileIdInformation>()))
        {
            throw new IOException(
                "Could not read the physical extraction-directory identity.",
                new Win32Exception(Marshal.GetLastWin32Error()));
        }

        return new FileIdentity(
            information.VolumeSerialNumber,
            information.FileIdLow,
            information.FileIdHigh);
    }

    private static void MarkDeleteOnClose(SafeFileHandle handle)
    {
        var disposition = new FileDispositionInformation { DeleteFile = true };
        if (!SetFileInformationByHandle(
                handle,
                FileDispositionInfoClass,
                ref disposition,
                Marshal.SizeOf<FileDispositionInformation>()))
        {
            throw new IOException(
                "Could not mark the anchored extraction directory for deletion.",
                new Win32Exception(Marshal.GetLastWin32Error()));
        }
    }

    private static bool PathEntryExists(string path)
    {
        try
        {
            _ = File.GetAttributes(path);
            return true;
        }
        catch (FileNotFoundException)
        {
            return false;
        }
        catch (DirectoryNotFoundException)
        {
            return false;
        }
    }

    private readonly record struct FileIdentity(
        ulong VolumeSerialNumber,
        ulong FileIdLow,
        ulong FileIdHigh);

    [StructLayout(LayoutKind.Sequential)]
    private struct FileIdInformation
    {
        internal ulong VolumeSerialNumber;
        internal ulong FileIdLow;
        internal ulong FileIdHigh;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct FileDispositionInformation
    {
        [MarshalAs(UnmanagedType.U1)]
        internal bool DeleteFile;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct FileAttributeTagInformation
    {
        internal uint FileAttributes;
        internal uint ReparseTag;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeFileHandle CreateFileW(
        string fileName,
        uint desiredAccess,
        uint shareMode,
        IntPtr securityAttributes,
        uint creationDisposition,
        uint flagsAndAttributes,
        IntPtr templateFile);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetFileInformationByHandleEx(
        SafeFileHandle file,
        int fileInformationClass,
        out FileIdInformation fileInformation,
        int bufferSize);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetFileInformationByHandleEx(
        SafeFileHandle file,
        int fileInformationClass,
        out FileAttributeTagInformation fileInformation,
        int bufferSize);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetFileInformationByHandle(
        SafeFileHandle file,
        int fileInformationClass,
        ref FileDispositionInformation fileInformation,
        int bufferSize);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern uint GetFinalPathNameByHandleW(
        SafeFileHandle file,
        StringBuilder filePath,
        int filePathLength,
        uint flags);
}
