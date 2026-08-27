using System.Buffers.Binary;
using System.Runtime.InteropServices;

namespace ScreenFix.Windows.Tests;

public sealed class PublishedExecutableIconTests
{
    private const uint LoadLibraryAsDataFile = 0x00000002;
    private const uint LoadLibraryAsImageResource = 0x00000020;
    private const int ResourceTypeIcon = 3;
    private const int ResourceTypeGroupIcon = 14;
    private const int ErrorResourceTypeNotFound = 1813;
    private const int IcoDirectoryEntrySize = 16;
    private const int GroupIconDirectoryEntrySize = 14;
    private static readonly int[] ExpectedSizes = [16, 20, 24, 32, 40, 48, 64, 128, 256];
    private static readonly byte[] PngSignature = [137, 80, 78, 71, 13, 10, 26, 10];

    [Fact]
    public void PublishedExecutable_ContainsEveryNativeIconFrame()
    {
        var executable = GetRequiredFile("SCREENFIX_PUBLISHED_EXE");
        var canonicalIcon = GetRequiredFile("SCREENFIX_CANONICAL_ICO");
        var canonicalFrames = ReadCanonicalFrames(canonicalIcon);
        var module = LoadLibraryExW(
            executable,
            nint.Zero,
            LoadLibraryAsDataFile | LoadLibraryAsImageResource);
        var loadError = module == nint.Zero ? Marshal.GetLastPInvokeError() : 0;
        Assert.True(
            module != nint.Zero,
            $"LoadLibraryExW failed for {executable} with error {loadError}.");

        EnumResourceNameProc? callback = null;
        try
        {
            var names = new List<ResourceName>();
            callback = (_, _, name, _) =>
            {
                names.Add(ReadResourceName(name));
                return true;
            };
            var enumerated = EnumResourceNamesW(
                module,
                (nint)ResourceTypeGroupIcon,
                callback,
                nint.Zero);
            var enumerationError = enumerated ? 0 : Marshal.GetLastPInvokeError();
            Assert.True(
                enumerated || enumerationError == ErrorResourceTypeNotFound,
                $"EnumResourceNamesW failed for {executable} with error {enumerationError}.");

            var candidateFailures = new List<string>();
            foreach (var name in names)
            {
                if (!TryReadResource(
                        module,
                        name,
                        ResourceTypeGroupIcon,
                        out var groupBytes,
                        out var readFailure))
                {
                    candidateFailures.Add($"{name}: {readFailure}");
                    continue;
                }

                if (!TryReadGroupEntries(groupBytes, out var entries, out var parseFailure))
                {
                    candidateFailures.Add($"{name}: {parseFailure}");
                    continue;
                }

                var sizes = entries.Select(entry => entry.Size).Order().ToArray();
                if (!sizes.SequenceEqual(ExpectedSizes))
                {
                    continue;
                }

                var payloadFailure = FindPayloadFailure(
                    module,
                    executable,
                    name,
                    entries,
                    canonicalFrames);
                if (payloadFailure is null)
                {
                    return;
                }

                candidateFailures.Add(payloadFailure);
            }

            var details = candidateFailures.Count == 0
                ? "No enumerated group had the exact nine-frame size set."
                : string.Join(" ", candidateFailures);
            Assert.Fail(
                $"{executable} does not contain an RT_GROUP_ICON with the exact Screen Patch " +
                $"frame set and payloads. {details}");
        }
        finally
        {
            GC.KeepAlive(callback);
            Assert.True(
                FreeLibrary(module),
                $"FreeLibrary failed for {executable} with error {Marshal.GetLastPInvokeError()}.");
        }
    }

    private static Dictionary<int, byte[]> ReadCanonicalFrames(string canonicalIcon)
    {
        var bytes = File.ReadAllBytes(canonicalIcon);
        Assert.True(bytes.Length >= 6, $"Canonical ICO is truncated: {canonicalIcon}.");
        Assert.Equal((ushort)0, ReadUInt16(bytes, 0));
        Assert.Equal((ushort)1, ReadUInt16(bytes, 2));
        var count = ReadUInt16(bytes, 4);
        Assert.True(
            bytes.Length >= 6 + (count * IcoDirectoryEntrySize),
            $"Canonical ICO directory is truncated: {canonicalIcon}.");

        var frames = new Dictionary<int, byte[]>();
        for (var index = 0; index < count; index++)
        {
            var entryOffset = 6 + (index * IcoDirectoryEntrySize);
            var width = DecodeSize(bytes[entryOffset]);
            var height = DecodeSize(bytes[entryOffset + 1]);
            Assert.Equal(width, height);
            var payloadLength = ReadUInt32(bytes, entryOffset + 8);
            var payloadOffset = ReadUInt32(bytes, entryOffset + 12);
            Assert.True(
                payloadOffset <= bytes.Length && payloadLength <= bytes.Length - payloadOffset,
                $"Canonical ICO frame {width} is outside {canonicalIcon}.");
            var payload = bytes.AsSpan((int)payloadOffset, (int)payloadLength).ToArray();
            Assert.True(
                payload.AsSpan().StartsWith(PngSignature),
                $"Canonical ICO frame {width} is not PNG data in {canonicalIcon}.");
            Assert.True(
                frames.TryAdd(width, payload),
                $"Canonical ICO contains duplicate {width}-pixel frames: {canonicalIcon}.");
        }

        Assert.Equal(ExpectedSizes, frames.Keys.Order().ToArray());
        return frames;
    }

    private static string? FindPayloadFailure(
        nint module,
        string executable,
        ResourceName groupName,
        IReadOnlyList<GroupIconEntry> entries,
        IReadOnlyDictionary<int, byte[]> canonicalFrames)
    {
        foreach (var entry in entries)
        {
            if (!TryReadResource(
                    module,
                    ResourceName.FromInteger(entry.ResourceId),
                    ResourceTypeIcon,
                    out var payload,
                    out var readFailure))
            {
                return $"{executable}, group {groupName}, frame {entry.Size}: {readFailure}";
            }

            var canonicalPayload = canonicalFrames[entry.Size];
            if (entry.DeclaredBytes != payload.Length)
            {
                return $"{executable}, group {groupName}, frame {entry.Size}: group declares " +
                    $"{entry.DeclaredBytes} bytes but RT_ICON contains {payload.Length}.";
            }

            if (!payload.AsSpan().SequenceEqual(canonicalPayload))
            {
                return $"{executable}, group {groupName}, frame {entry.Size}: RT_ICON payload " +
                    $"differs from the canonical PNG ({payload.Length} versus " +
                    $"{canonicalPayload.Length} bytes).";
            }
        }

        return null;
    }

    private static bool TryReadGroupEntries(
        byte[] bytes,
        out IReadOnlyList<GroupIconEntry> entries,
        out string failure)
    {
        entries = [];
        if (bytes.Length < 6)
        {
            failure = "GRPICONDIR is truncated.";
            return false;
        }

        if (ReadUInt16(bytes, 0) != 0 || ReadUInt16(bytes, 2) != 1)
        {
            failure = "GRPICONDIR has an invalid header.";
            return false;
        }

        var count = ReadUInt16(bytes, 4);
        if (bytes.Length < 6 + (count * GroupIconDirectoryEntrySize))
        {
            failure = "GRPICONDIR entries are truncated.";
            return false;
        }

        var parsedEntries = new List<GroupIconEntry>(count);
        for (var index = 0; index < count; index++)
        {
            var offset = 6 + (index * GroupIconDirectoryEntrySize);
            var width = DecodeSize(bytes[offset]);
            var height = DecodeSize(bytes[offset + 1]);
            if (width != height)
            {
                failure = $"GRPICONDIR frame is not square: {width}x{height}.";
                return false;
            }

            parsedEntries.Add(new GroupIconEntry(
                width,
                ReadUInt32(bytes, offset + 8),
                ReadUInt16(bytes, offset + 12)));
        }

        entries = parsedEntries;
        failure = string.Empty;
        return true;
    }

    private static bool TryReadResource(
        nint module,
        ResourceName name,
        int type,
        out byte[] bytes,
        out string failure)
    {
        var lookup = WithResourceName(name, pointer =>
        {
            var resource = FindResourceW(module, pointer, (nint)type);
            var error = resource == nint.Zero ? Marshal.GetLastPInvokeError() : 0;
            return (Resource: resource, Error: error);
        });
        if (lookup.Resource == nint.Zero)
        {
            bytes = [];
            failure = $"FindResourceW type {type} failed with error {lookup.Error}.";
            return false;
        }

        var size = SizeofResource(module, lookup.Resource);
        var sizeError = size == 0 ? Marshal.GetLastPInvokeError() : 0;
        if (size == 0)
        {
            bytes = [];
            failure = $"SizeofResource type {type} returned zero with error {sizeError}.";
            return false;
        }

        var loaded = LoadResource(module, lookup.Resource);
        var loadError = loaded == nint.Zero ? Marshal.GetLastPInvokeError() : 0;
        if (loaded == nint.Zero)
        {
            bytes = [];
            failure = $"LoadResource type {type} failed with error {loadError}.";
            return false;
        }

        var pointer = LockResource(loaded);
        if (pointer == nint.Zero)
        {
            bytes = [];
            failure = $"LockResource type {type} returned null.";
            return false;
        }

        bytes = new byte[checked((int)size)];
        Marshal.Copy(pointer, bytes, 0, bytes.Length);
        failure = string.Empty;
        return true;
    }

    private static ResourceName ReadResourceName(nint name)
    {
        if (((nuint)name >> 16) == 0)
        {
            return ResourceName.FromInteger((ushort)(nuint)name);
        }

        return ResourceName.FromString(
            Marshal.PtrToStringUni(name) ?? throw new InvalidOperationException(
                "EnumResourceNamesW returned an invalid string resource name."));
    }

    private static TResult WithResourceName<TResult>(
        ResourceName name,
        Func<nint, TResult> action)
    {
        if (name.IntegerId is ushort integerId)
        {
            return action((nint)integerId);
        }

        var pointer = Marshal.StringToHGlobalUni(name.Text);
        try
        {
            return action(pointer);
        }
        finally
        {
            Marshal.FreeHGlobal(pointer);
        }
    }

    private static string GetRequiredFile(string environmentVariable)
    {
        var value = Environment.GetEnvironmentVariable(environmentVariable);
        Assert.False(
            string.IsNullOrWhiteSpace(value),
            $"Required environment variable {environmentVariable} is not set.");
        var path = Path.GetFullPath(value);
        Assert.True(File.Exists(path), $"Required file from {environmentVariable} does not exist: {path}.");
        return path;
    }

    private static int DecodeSize(byte value) => value == 0 ? 256 : value;

    private static ushort ReadUInt16(byte[] bytes, int offset) =>
        BinaryPrimitives.ReadUInt16LittleEndian(bytes.AsSpan(offset, sizeof(ushort)));

    private static uint ReadUInt32(byte[] bytes, int offset) =>
        BinaryPrimitives.ReadUInt32LittleEndian(bytes.AsSpan(offset, sizeof(uint)));

    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private delegate bool EnumResourceNameProc(
        nint module,
        nint type,
        nint name,
        nint parameter);

    private readonly record struct ResourceName(ushort? IntegerId, string? Text)
    {
        internal static ResourceName FromInteger(ushort value) => new(value, null);

        internal static ResourceName FromString(string value) => new(null, value);

        public override string ToString() => IntegerId is ushort value ? $"#{value}" : Text!;
    }

    private readonly record struct GroupIconEntry(
        int Size,
        uint DeclaredBytes,
        ushort ResourceId);

    [DllImport("kernel32.dll", EntryPoint = "LoadLibraryExW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern nint LoadLibraryExW(string fileName, nint file, uint flags);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool FreeLibrary(nint module);

    [DllImport("kernel32.dll", EntryPoint = "EnumResourceNamesW", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool EnumResourceNamesW(
        nint module,
        nint type,
        EnumResourceNameProc callback,
        nint parameter);

    [DllImport("kernel32.dll", EntryPoint = "FindResourceW", SetLastError = true)]
    private static extern nint FindResourceW(nint module, nint name, nint type);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint SizeofResource(nint module, nint resource);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern nint LoadResource(nint module, nint resource);

    [DllImport("kernel32.dll")]
    private static extern nint LockResource(nint resource);
}
