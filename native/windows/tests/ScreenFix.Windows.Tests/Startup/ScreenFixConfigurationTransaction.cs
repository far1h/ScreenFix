using System.Diagnostics;
using System.Runtime.ExceptionServices;
using ScreenFix.App;

namespace ScreenFix.Windows.Tests.Startup;

internal interface IConfigurationFileSystem
{
    bool DirectoryExists(string path);

    bool FileExists(string path);

    FileAttributes GetAttributes(string path);

    void MoveDirectory(string source, string destination);

    void DeleteDirectory(string path);
}

internal interface IConfigurationProcess : IDisposable
{
    bool HasExited { get; }

    bool WaitForInputIdle(TimeSpan timeout);

    void Kill();

    bool WaitForExit(TimeSpan timeout);
}

internal interface IConfigurationMonotonicClock
{
    long GetTimestamp();

    TimeSpan GetElapsedTime(long startingTimestamp);
}

internal interface IConfigurationProcessFactory
{
    ConfigurationProcessLaunch Start(
        ConfigurationLaunchRequest request,
        IConfigurationMonotonicClock clock);
}

internal sealed record ConfigurationProcessLaunch(
    IConfigurationProcess Process,
    long StartingTimestamp);

internal sealed record ConfigurationLaunchRequest(
    string Executable,
    string BundleExtractionBaseDirectory);

internal interface IConfigurationMutexObserver
{
    bool WaitUntilCreated(
        IConfigurationProcess process,
        string mutexName,
        TimeSpan timeout);
}

internal sealed record ScreenFixConfigurationTransactionDependencies(
    string LocalAppData,
    string ConfigFile,
    Func<IDisposable?> TryAcquireGate,
    IConfigurationFileSystem FileSystem,
    IConfigurationProcessFactory ProcessFactory,
    IConfigurationMutexObserver MutexObserver,
    IConfigurationMonotonicClock Clock)
{
    internal static ScreenFixConfigurationTransactionDependencies Production()
    {
        return new ScreenFixConfigurationTransactionDependencies(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            ScreenFixPaths.ConfigFile,
            ScreenFixApplicationIdentity.TryAcquire,
            new SystemConfigurationFileSystem(),
            new SystemConfigurationProcessFactory(),
            new SystemConfigurationMutexObserver(),
            new StopwatchConfigurationClock());
    }
}

internal sealed class ScreenFixConfigurationTransaction : IDisposable
{
    private readonly ScreenFixConfigurationTransactionDependencies dependencies;
    private readonly string configDirectory;
    private readonly bool hadOriginalConfiguration;
    private IDisposable? gate;
    private IConfigurationProcess? unprovenChild;
    private bool preservePaths;
    private bool disposed;

    internal ScreenFixConfigurationTransaction(bool allowDisposableAccountMutation)
        : this(
            allowDisposableAccountMutation,
            ScreenFixConfigurationTransactionDependencies.Production())
    {
    }

    internal ScreenFixConfigurationTransaction(
        bool allowDisposableAccountMutation,
        ScreenFixConfigurationTransactionDependencies dependencies)
    {
        ArgumentNullException.ThrowIfNull(dependencies);
        if (!allowDisposableAccountMutation)
        {
            throw new InvalidOperationException(
                "Configuration isolation requires explicit disposable-account opt-in.");
        }

        this.dependencies = dependencies;
        gate = dependencies.TryAcquireGate()
            ?? throw new InvalidOperationException(
                "Configuration isolation requires a fresh production mutex.");

        try
        {
            var localAppData = NormalizeAbsoluteNonRoot(
                dependencies.LocalAppData,
                "Local AppData");
            var configFile = NormalizeAbsoluteNonRoot(
                dependencies.ConfigFile,
                "configuration file");
            configDirectory = Path.GetDirectoryName(configFile)
                ?? throw new InvalidOperationException(
                    "Configuration file must have a parent directory.");
            RequireStrictChild(localAppData, configDirectory);
            ValidateExistingAncestors(configDirectory);
            BackupDirectory = CreateBackupPath(configDirectory);
            hadOriginalConfiguration = dependencies.FileSystem.DirectoryExists(configDirectory);
            if (hadOriginalConfiguration)
            {
                dependencies.FileSystem.MoveDirectory(configDirectory, BackupDirectory);
            }
        }
        catch
        {
            gate.Dispose();
            gate = null;
            throw;
        }
    }

    internal string BackupDirectory { get; }

    internal bool CanCleanExternalState => !preservePaths && gate is not null;

    internal TimeSpan RunLaunch(ConfigurationLaunchRequest request, TimeSpan timeout)
    {
        ArgumentNullException.ThrowIfNull(request);
        ObjectDisposedException.ThrowIf(disposed, this);
        if (gate is null || preservePaths)
        {
            throw new InvalidOperationException(
                "Configuration transaction no longer owns the production mutex.");
        }

        if (timeout <= TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(timeout));
        }

        var exactExecutable = NormalizeAbsoluteNonRoot(
            request.Executable,
            "published executable");
        if (!dependencies.FileSystem.FileExists(exactExecutable))
        {
            throw new FileNotFoundException(
                "Published executable does not exist.",
                exactExecutable);
        }

        var extractionBaseDirectory = NormalizeAbsoluteNonRoot(
            request.BundleExtractionBaseDirectory,
            "bundle extraction base directory");
        if (!dependencies.FileSystem.DirectoryExists(extractionBaseDirectory))
        {
            throw new DirectoryNotFoundException(
                $"Bundle extraction base directory does not exist: {extractionBaseDirectory}");
        }

        ValidateExistingAncestors(configDirectory);
        if (dependencies.FileSystem.DirectoryExists(configDirectory))
        {
            throw new InvalidOperationException(
                "ScreenFix configuration must be absent before child launch.");
        }

        gate.Dispose();
        gate = null;

        Exception? launchFailure = null;
        IConfigurationProcess? child = null;
        TimeSpan? startupElapsed = null;
        var terminationProven = true;
        try
        {
            var launch = dependencies.ProcessFactory.Start(
                new ConfigurationLaunchRequest(exactExecutable, extractionBaseDirectory),
                dependencies.Clock);
            child = launch.Process;
            try
            {
                var remaining = RemainingStartupTime(launch.StartingTimestamp, timeout);
                if (remaining <= TimeSpan.Zero)
                {
                    throw new TimeoutException(
                        "Exact child exhausted the cumulative startup deadline before mutex observation.");
                }

                if (!dependencies.MutexObserver.WaitUntilCreated(
                        child,
                        ScreenFixApplicationIdentity.SingleInstanceMutexName,
                        remaining))
                {
                    throw new InvalidOperationException(
                        "Exact child exited or timed out before creating the production mutex.");
                }

                if (child.HasExited)
                {
                    throw new InvalidOperationException(
                        "Exact child exited before reaching input-idle.");
                }

                remaining = RemainingStartupTime(launch.StartingTimestamp, timeout);
                if (remaining <= TimeSpan.Zero)
                {
                    throw new TimeoutException(
                        "Exact child exhausted the cumulative startup deadline before input-idle.");
                }

                if (!child.WaitForInputIdle(remaining))
                {
                    throw child.HasExited
                        ? new InvalidOperationException(
                            "Exact child exited before reaching input-idle.")
                        : new TimeoutException(
                            "Exact child did not reach input-idle before the timeout.");
                }

                startupElapsed = dependencies.Clock.GetElapsedTime(launch.StartingTimestamp);
                if (startupElapsed >= timeout)
                {
                    throw new TimeoutException(
                        "Exact child reached input-idle after the cumulative startup deadline.");
                }

                if (child.HasExited)
                {
                    throw new InvalidOperationException(
                        "Exact child exited immediately after reaching input-idle.");
                }
            }
            catch (Exception error)
            {
                launchFailure = error;
            }
            finally
            {
                var termination = TerminateAndWait(child, timeout);
                terminationProven = termination.Proven;
                if (termination.Error is not null)
                {
                    launchFailure = CombineFailures(launchFailure, termination.Error);
                }

                if (terminationProven)
                {
                    try
                    {
                        child.Dispose();
                    }
                    catch (Exception error)
                    {
                        launchFailure = CombineFailures(launchFailure, error);
                    }
                }
            }
        }
        catch (Exception error)
        {
            launchFailure ??= error;
        }

        if (!terminationProven)
        {
            preservePaths = true;
            unprovenChild = child;
            throw RecoveryFailure(
                "Exact-child termination could not be proven; configuration paths were preserved.",
                launchFailure);
        }

        preservePaths = true;
        try
        {
            gate = dependencies.TryAcquireGate();
        }
        catch (Exception error)
        {
            var inner = launchFailure is null
                ? error
                : CombineFailures(launchFailure, error);
            throw RecoveryFailure(
                "Production mutex reacquisition failed after child exit; configuration paths were preserved.",
                inner);
        }

        if (gate is null)
        {
            throw RecoveryFailure(
                "A fresh production mutex could not be created after child exit; configuration paths were preserved.",
                launchFailure);
        }

        preservePaths = false;

        ValidateExistingAncestors(configDirectory);
        if (dependencies.FileSystem.DirectoryExists(configDirectory))
        {
            dependencies.FileSystem.DeleteDirectory(configDirectory);
        }

        if (launchFailure is not null)
        {
            ExceptionDispatchInfo.Capture(launchFailure).Throw();
        }

        return startupElapsed
            ?? throw new InvalidOperationException(
                "Exact child did not produce a startup measurement.");
    }

    private TimeSpan RemainingStartupTime(long startingTimestamp, TimeSpan timeout)
    {
        var elapsed = dependencies.Clock.GetElapsedTime(startingTimestamp);
        if (elapsed < TimeSpan.Zero)
        {
            throw new InvalidOperationException("The startup monotonic clock moved backwards.");
        }

        return elapsed >= timeout ? TimeSpan.Zero : timeout - elapsed;
    }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }

        disposed = true;
        if (preservePaths)
        {
            unprovenChild?.Dispose();
            unprovenChild = null;
            gate?.Dispose();
            gate = null;
            return;
        }

        var ownedGate = gate;
        gate = null;
        if (ownedGate is null)
        {
            return;
        }

        try
        {
            if (hadOriginalConfiguration)
            {
                ValidateRequiredBackupForRestore();
            }

            ValidateExistingAncestors(configDirectory);
            if (dependencies.FileSystem.DirectoryExists(configDirectory))
            {
                dependencies.FileSystem.DeleteDirectory(configDirectory);
            }

            if (hadOriginalConfiguration)
            {
                dependencies.FileSystem.MoveDirectory(BackupDirectory, configDirectory);
            }
        }
        catch (Exception error)
        {
            preservePaths = true;
            throw RecoveryFailure(
                "Configuration cleanup or restoration failed; recovery paths were preserved.",
                error);
        }
        finally
        {
            ownedGate.Dispose();
        }
    }

    private static (bool Proven, Exception? Error) TerminateAndWait(
        IConfigurationProcess child,
        TimeSpan timeout)
    {
        Exception? failure = null;
        try
        {
            if (!child.HasExited)
            {
                child.Kill();
            }
        }
        catch (Exception error)
        {
            failure = error;
        }

        try
        {
            return (child.WaitForExit(timeout), failure);
        }
        catch (Exception error)
        {
            return (false, CombineFailures(failure, error));
        }
    }

    private static Exception CombineFailures(Exception? first, Exception second)
    {
        return first is null ? second : new AggregateException(first, second);
    }

    private InvalidOperationException RecoveryFailure(string message, Exception? inner)
    {
        return new InvalidOperationException(
            $"{message} Test path: {configDirectory}. Backup path: {BackupDirectory}.",
            inner);
    }

    private void ValidateRequiredBackupForRestore()
    {
        var backup = NormalizeAbsoluteNonRoot(BackupDirectory, "configuration backup");
        var configParent = Path.GetDirectoryName(configDirectory);
        var backupParent = Path.GetDirectoryName(backup);
        var expectedPrefix = configDirectory + ".backup-";
        var suffix = backup.StartsWith(expectedPrefix, StringComparison.OrdinalIgnoreCase)
            ? backup[expectedPrefix.Length..]
            : string.Empty;
        if (configParent is null
            || backupParent is null
            || !Path.TrimEndingDirectorySeparator(configParent).Equals(
                Path.TrimEndingDirectorySeparator(backupParent),
                StringComparison.OrdinalIgnoreCase)
            || !Guid.TryParseExact(suffix, "N", out _))
        {
            throw new IOException(
                $"Configuration backup is not the expected sibling: {backup}");
        }

        ValidateExistingAncestors(backup);
        if (!dependencies.FileSystem.DirectoryExists(backup))
        {
            throw new IOException($"Configuration backup is missing: {backup}");
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
        if (string.IsNullOrEmpty(root)
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
                "ScreenFix configuration must be a strict child of Local AppData.");
        }
    }

    private void ValidateExistingAncestors(string candidate)
    {
        var current = candidate;
        while (true)
        {
            FileAttributes? attributes = null;
            try
            {
                attributes = dependencies.FileSystem.GetAttributes(current);
            }
            catch (FileNotFoundException)
            {
            }
            catch (DirectoryNotFoundException)
            {
            }

            if (attributes.HasValue
                && (attributes & FileAttributes.ReparsePoint) != 0)
            {
                throw new InvalidOperationException(
                    $"Configuration path ancestor is a reparse point: {current}");
            }

            if (attributes.HasValue
                && (attributes & FileAttributes.Directory) == 0)
            {
                throw new InvalidOperationException(
                    $"Configuration path ancestor is not a directory: {current}");
            }

            var parent = Path.GetDirectoryName(current);
            if (parent is null || parent == current)
            {
                return;
            }

            current = parent;
        }
    }

    private string CreateBackupPath(string directory)
    {
        while (true)
        {
            var candidate = directory + ".backup-" + Guid.NewGuid().ToString("N");
            if (!PathEntryExists(candidate))
            {
                return candidate;
            }
        }
    }

    private bool PathEntryExists(string path)
    {
        try
        {
            dependencies.FileSystem.GetAttributes(path);
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
}

internal sealed class SystemConfigurationFileSystem : IConfigurationFileSystem
{
    public bool DirectoryExists(string path) => Directory.Exists(path);

    public bool FileExists(string path) => File.Exists(path);

    public FileAttributes GetAttributes(string path) => File.GetAttributes(path);

    public void MoveDirectory(string source, string destination) =>
        Directory.Move(source, destination);

    public void DeleteDirectory(string path) => Directory.Delete(path, recursive: true);
}

internal sealed class SystemConfigurationProcessFactory : IConfigurationProcessFactory
{
    public ConfigurationProcessLaunch Start(
        ConfigurationLaunchRequest request,
        IConfigurationMonotonicClock clock)
    {
        var startInfo = CreateStartInfo(request);
        var startingTimestamp = clock.GetTimestamp();
        var process = Process.Start(startInfo)
            ?? throw new InvalidOperationException(
                $"Failed to start exact child: {request.Executable}");
        return new ConfigurationProcessLaunch(
            new SystemConfigurationProcess(process),
            startingTimestamp);
    }

    internal static ProcessStartInfo CreateStartInfo(ConfigurationLaunchRequest request)
    {
        var startInfo = new ProcessStartInfo
        {
            FileName = request.Executable,
            UseShellExecute = false,
        };
        startInfo.Environment["DOTNET_BUNDLE_EXTRACT_BASE_DIR"] =
            request.BundleExtractionBaseDirectory;
        return startInfo;
    }
}

internal sealed class SystemConfigurationProcess(Process process) : IConfigurationProcess
{
    public bool HasExited => process.HasExited;

    public bool WaitForInputIdle(TimeSpan timeout) => process.WaitForInputIdle(timeout);

    public void Kill() => process.Kill();

    public bool WaitForExit(TimeSpan timeout) => process.WaitForExit(timeout);

    public void Dispose() => process.Dispose();
}

internal sealed class StopwatchConfigurationClock : IConfigurationMonotonicClock
{
    public long GetTimestamp() => Stopwatch.GetTimestamp();

    public TimeSpan GetElapsedTime(long startingTimestamp) =>
        Stopwatch.GetElapsedTime(startingTimestamp);
}

internal sealed class SystemConfigurationMutexObserver : IConfigurationMutexObserver
{
    public bool WaitUntilCreated(
        IConfigurationProcess process,
        string mutexName,
        TimeSpan timeout)
    {
        var timer = Stopwatch.StartNew();
        while (timer.Elapsed <= timeout)
        {
            if (process.HasExited)
            {
                return false;
            }

            if (Mutex.TryOpenExisting(mutexName, out var observer))
            {
                using (observer)
                {
                    return true;
                }
            }

            Thread.Yield();
        }

        return false;
    }
}
