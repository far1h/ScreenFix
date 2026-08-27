using System.Buffers.Binary;
using System.IO.Compression;
using System.Text;

namespace ScreenFix.PackageVerifier.Bundle;

internal sealed record ExtractedBundleAssembly(BundleEntry Entry, byte[] Bytes)
{
    internal long DeclaredSize => Entry.Size;

    internal long StoredSize => Entry.StoredSize;

    internal bool IsCompressed => Entry.IsCompressed;
}

internal static class SingleFileBundleReader
{
    internal const long MaximumBundleBytes = 512L * 1024 * 1024;
    internal const long MaximumEntryBytes = 256L * 1024 * 1024;
    internal const long MaximumAppAssemblyBytes = 16L * 1024 * 1024;
    internal const int MaximumEntries = 4096;
    internal const int MaximumPathBytes = 1024;
    internal const uint RequiredMajorVersion = 6;
    internal const uint RequiredMinorVersion = 0;

    private const int SignatureScanBufferSize = 64 * 1024;

    private static readonly byte[] Signature =
    [
        0x8b, 0x12, 0x02, 0xb9, 0x6a, 0x61, 0x20, 0x38,
        0x72, 0x7b, 0x93, 0x02, 0x14, 0xd7, 0xa0, 0x32,
        0x13, 0xf5, 0xb9, 0xe6, 0xef, 0xae, 0x33, 0x18,
        0xee, 0x3b, 0x2d, 0xce, 0x24, 0xb3, 0x6a, 0xae,
    ];

    private static readonly Encoding StrictUtf8 =
        new UTF8Encoding(encoderShouldEmitUTF8Identifier: false, throwOnInvalidBytes: true);

    private static readonly int[] SignaturePrefixLengths = BuildPrefixLengths(Signature);

    internal static ExtractedBundleAssembly ExtractScreenFixAssembly(
        string path,
        BundleCompressionMode expectedMode)
    {
        try
        {
            return ExtractScreenFixAssemblyCore(path, expectedMode);
        }
        catch (EndOfStreamException exception)
        {
            throw new InvalidDataException("bundle manifest is truncated", exception);
        }
    }

    private static ExtractedBundleAssembly ExtractScreenFixAssemblyCore(
        string path,
        BundleCompressionMode expectedMode)
    {
        using var stream = new FileStream(
            path,
            FileMode.Open,
            FileAccess.Read,
            FileShare.Read,
            bufferSize: 4096,
            FileOptions.SequentialScan);

        if (stream.Length == 0)
        {
            throw new InvalidDataException("bundle file must be nonempty");
        }

        if (stream.Length > MaximumBundleBytes)
        {
            throw new InvalidDataException("bundle file exceeds 512 MiB");
        }

        var signatureOffset = FindSignature(stream);
        if (signatureOffset < sizeof(long))
        {
            throw new InvalidDataException(
                "bundle header offset slot is outside the file");
        }

        stream.Position = signatureOffset - sizeof(long);
        var manifestOffset = ReadInt64(stream);
        if (manifestOffset <= signatureOffset + Signature.Length)
        {
            throw new InvalidDataException(
                "bundle header offset precedes the signature");
        }

        if (manifestOffset >= stream.Length)
        {
            throw new InvalidDataException(
                "bundle header offset is outside the file");
        }

        stream.Position = manifestOffset;

        var majorVersion = ReadUInt32(stream);
        var minorVersion = ReadUInt32(stream);
        if (majorVersion != RequiredMajorVersion || minorVersion != RequiredMinorVersion)
        {
            throw new InvalidDataException("bundle version must be 6.0");
        }

        var entryCount = ReadInt32(stream);
        if (entryCount is < 1 or > MaximumEntries)
        {
            throw new InvalidDataException(
                "bundle entry count must be between 1 and 4096");
        }

        _ = ReadString(stream, MaximumPathBytes, "bundle ID");
        var depsJsonOffset = ReadInt64(stream);
        var depsJsonSize = ReadInt64(stream);
        var runtimeConfigOffset = ReadInt64(stream);
        var runtimeConfigSize = ReadInt64(stream);
        var flags = ReadUInt64(stream);
        ValidateHeaderFlags(flags);
        ValidateLocationShape(depsJsonOffset, depsJsonSize, "deps.json");
        ValidateLocationShape(
            runtimeConfigOffset,
            runtimeConfigSize,
            "runtimeconfig.json");

        var entries = new List<BundleEntry>(entryCount);
        var paths = new HashSet<string>(StringComparer.Ordinal);
        for (var index = 0; index < entryCount; index++)
        {
            var entry = ReadEntry(stream, manifestOffset);
            if (!paths.Add(entry.RelativePath))
            {
                var appDiagnostic = entry.RelativePath == "ScreenFix.dll"
                    ? ": duplicate ScreenFix.dll"
                    : string.Empty;
                throw new InvalidDataException(
                    $"bundle entry path is duplicated{appDiagnostic}");
            }

            entries.Add(entry);
        }

        if (stream.Position != stream.Length)
        {
            throw new InvalidDataException("bundle manifest has trailing bytes");
        }

        ValidateEntrySet(entries, manifestOffset);
        ValidateHeaderLocation(
            entries,
            depsJsonOffset,
            depsJsonSize,
            BundleFileType.DepsJson,
            "deps.json");
        ValidateHeaderLocation(
            entries,
            runtimeConfigOffset,
            runtimeConfigSize,
            BundleFileType.RuntimeConfigJson,
            "runtimeconfig.json");

        var assemblies = entries
            .Where(entry => entry.RelativePath == "ScreenFix.dll")
            .ToArray();
        if (assemblies.Length == 0)
        {
            throw new InvalidDataException("ScreenFix.dll assembly is missing");
        }

        if (assemblies.Length > 1)
        {
            throw new InvalidDataException("duplicate ScreenFix.dll assembly");
        }

        var assembly = assemblies[0];
        if (assembly.FileType != BundleFileType.Assembly)
        {
            throw new InvalidDataException(
                "ScreenFix.dll must have Assembly file type");
        }

        if (assembly.Size > MaximumAppAssemblyBytes)
        {
            throw new InvalidDataException(
                "ScreenFix.dll declared size exceeds 16 MiB");
        }

        if (expectedMode == BundleCompressionMode.Compressed && !assembly.IsCompressed)
        {
            throw new InvalidDataException(
                "expected compressed ScreenFix.dll but CompressedSize is zero");
        }

        if (expectedMode == BundleCompressionMode.Uncompressed && assembly.IsCompressed)
        {
            throw new InvalidDataException(
                "expected uncompressed ScreenFix.dll but CompressedSize is positive");
        }

        var bytes = assembly.IsCompressed
            ? ExtractCompressedAssembly(stream, assembly)
            : ExtractRawAssembly(stream, assembly);
        return new ExtractedBundleAssembly(assembly, bytes);
    }

    private static BundleEntry ReadEntry(Stream stream, long manifestOffset)
    {
        var offset = ReadInt64(stream);
        var size = ReadInt64(stream);
        var compressedSize = ReadInt64(stream);
        var fileType = (BundleFileType)ReadByte(stream);
        var relativePath = ReadString(
            stream,
            MaximumPathBytes,
            "bundle entry path");
        return BundleEntry.CreateValidated(
            offset,
            size,
            compressedSize,
            fileType,
            relativePath,
            manifestOffset);
    }

    private static byte[] ExtractRawAssembly(Stream stream, BundleEntry assembly)
    {
        stream.Position = assembly.Offset;
        var bytes = new byte[checked((int)assembly.Size)];
        try
        {
            stream.ReadExactly(bytes);
        }
        catch (EndOfStreamException exception)
        {
            throw new InvalidDataException(
                "raw ScreenFix.dll payload is truncated",
                exception);
        }

        return bytes;
    }

    private static byte[] ExtractCompressedAssembly(
        Stream stream,
        BundleEntry assembly)
    {
        if (!AppContext.TryGetSwitch(
                "System.IO.Compression.UseStrictValidation",
                out var strictValidation)
            || !strictValidation)
        {
            throw new InvalidDataException(
                "strict deflate validation is not enabled");
        }

        using var bounded = new SingleByteBoundedReadStream(
            stream,
            assembly.Offset,
            assembly.CompressedSize,
            leaveOpen: true);
        using var deflate = new DeflateStream(
            bounded,
            CompressionMode.Decompress,
            leaveOpen: true);
        var declaredSize = checked((int)assembly.Size);
        var output = new byte[checked(declaredSize + 1)];
        var written = 0;
        var cleanEnd = false;

        try
        {
            while (written < output.Length)
            {
                var read = deflate.Read(output.AsSpan(written));
                if (read == 0)
                {
                    cleanEnd = true;
                    break;
                }

                written += read;
            }

            if (written == declaredSize && !cleanEnd)
            {
                Span<byte> probe = stackalloc byte[1];
                var read = deflate.Read(probe);
                if (read == 0)
                {
                    cleanEnd = true;
                }
                else
                {
                    output[written++] = probe[0];
                }
            }
        }
        catch (InvalidDataException exception)
        {
            throw ClassifyDeflateFailure(written, declaredSize, bounded, exception);
        }

        if (written > declaredSize)
        {
            throw new InvalidDataException(
                "decompressed ScreenFix.dll exceeds declared size");
        }

        if (written < declaredSize)
        {
            throw new InvalidDataException(
                "decompressed ScreenFix.dll is shorter than declared size");
        }

        if (!cleanEnd)
        {
            throw new InvalidDataException(
                "compressed ScreenFix.dll payload is not cleanly terminated");
        }

        if (bounded.Remaining != 0)
        {
            throw new InvalidDataException(
                "compressed ScreenFix.dll payload has trailing bytes; "
                + "compressed ScreenFix.dll span was not fully consumed");
        }

        Array.Resize(ref output, declaredSize);
        return output;
    }

    private static InvalidDataException ClassifyDeflateFailure(
        int written,
        int declaredSize,
        SingleByteBoundedReadStream bounded,
        InvalidDataException exception)
    {
        if (written == declaredSize)
        {
            return new InvalidDataException(
                "compressed ScreenFix.dll payload is not cleanly terminated",
                exception);
        }

        if (bounded.Remaining == 0)
        {
            return new InvalidDataException(
                "compressed ScreenFix.dll payload is truncated",
                exception);
        }

        return new InvalidDataException(
            "compressed ScreenFix.dll payload is corrupt",
            exception);
    }

    private static void ValidateEntrySet(
        IReadOnlyCollection<BundleEntry> entries,
        long manifestOffset)
    {
        long cumulativeSize = 0;
        foreach (var entry in entries)
        {
            try
            {
                cumulativeSize = checked(cumulativeSize + entry.Size);
            }
            catch (OverflowException exception)
            {
                throw new InvalidDataException(
                    "cumulative bundle entry size overflows",
                    exception);
            }

            if (cumulativeSize > MaximumBundleBytes)
            {
                throw new InvalidDataException(
                    "cumulative bundle entry size exceeds 512 MiB");
            }
        }

        long previousEnd = 0;
        foreach (var entry in entries.OrderBy(entry => entry.Offset))
        {
            if (entry.Offset < previousEnd)
            {
                throw new InvalidDataException(
                    "bundle entry payload spans overlap");
            }

            previousEnd = checked(entry.Offset + entry.StoredSize);
        }

        if (previousEnd > manifestOffset)
        {
            throw new InvalidDataException(
                "bundle entry payload extends into the manifest");
        }
    }

    private static void ValidateHeaderFlags(ulong flags)
    {
        const ulong knownFlags = 1;
        if ((flags & ~knownFlags) != 0)
        {
            throw new InvalidDataException("bundle header flags are unknown");
        }
    }

    private static void ValidateLocationShape(long offset, long size, string name)
    {
        if ((offset == 0) != (size == 0) || offset < 0 || size < 0)
        {
            throw new InvalidDataException(
                $"bundle {name} location is invalid");
        }
    }

    private static void ValidateHeaderLocation(
        IReadOnlyCollection<BundleEntry> entries,
        long offset,
        long size,
        BundleFileType fileType,
        string name)
    {
        var matchingEntries = entries
            .Where(entry => entry.FileType == fileType)
            .ToArray();
        if (offset == 0 && matchingEntries.Length == 0)
        {
            return;
        }

        if (matchingEntries.Length != 1
            || matchingEntries[0].Offset != offset
            || matchingEntries[0].Size != size)
        {
            throw new InvalidDataException(
                $"bundle {name} location is invalid");
        }
    }

    internal static long FindSignature(Stream stream)
    {
        var buffer = new byte[SignatureScanBufferSize];
        var firstOffset = -1L;
        var matches = 0;
        var matched = 0;
        var blockOffset = stream.Position;
        while (true)
        {
            var bytesRead = stream.Read(buffer.AsSpan());
            if (bytesRead == 0)
            {
                break;
            }

            for (var index = 0; index < bytesRead; index++)
            {
                var value = buffer[index];
                while (matched > 0 && value != Signature[matched])
                {
                    matched = SignaturePrefixLengths[matched - 1];
                }

                if (value == Signature[matched])
                {
                    matched++;
                }

                if (matched == Signature.Length)
                {
                    matches++;
                    firstOffset = firstOffset < 0
                        ? blockOffset + index - Signature.Length + 1
                        : firstOffset;
                    matched = SignaturePrefixLengths[matched - 1];
                }
            }

            blockOffset += bytesRead;
        }

        return matches switch
        {
            0 => throw new InvalidDataException("bundle signature is missing"),
            1 => firstOffset,
            _ => throw new InvalidDataException(
                "bundle signature appears more than once"),
        };
    }

    private static int[] BuildPrefixLengths(ReadOnlySpan<byte> value)
    {
        var prefixLengths = new int[value.Length];
        var matched = 0;
        for (var index = 1; index < value.Length; index++)
        {
            while (matched > 0 && value[index] != value[matched])
            {
                matched = prefixLengths[matched - 1];
            }

            if (value[index] == value[matched])
            {
                matched++;
            }

            prefixLengths[index] = matched;
        }

        return prefixLengths;
    }

    private static string ReadString(Stream stream, int maximumBytes, string fieldName)
    {
        var length = Read7BitEncodedInt(stream);
        if (length > maximumBytes)
        {
            throw new InvalidDataException(
                $"{fieldName} exceeds {maximumBytes} UTF-8 bytes");
        }

        var bytes = new byte[length];
        stream.ReadExactly(bytes);
        try
        {
            return StrictUtf8.GetString(bytes);
        }
        catch (DecoderFallbackException exception)
        {
            throw new InvalidDataException(
                "manifest string is not valid UTF-8",
                exception);
        }
    }

    private static int Read7BitEncodedInt(Stream stream)
    {
        uint value = 0;
        var shift = 0;
        for (var index = 0; index < 5; index++)
        {
            var current = ReadByte(stream);
            if (index == 4 && (current & 0xf8) != 0)
            {
                throw new InvalidDataException(
                    (current & 0x80) != 0
                        ? "seven-bit string length is malformed"
                        : "seven-bit string length overflows");
            }

            value |= (uint)(current & 0x7f) << shift;
            if ((current & 0x80) == 0)
            {
                if (index > 0 && value < (1U << shift))
                {
                    throw new InvalidDataException(
                        "seven-bit string length is noncanonical");
                }

                return checked((int)value);
            }

            shift += 7;
        }

        throw new InvalidDataException("seven-bit string length is malformed");
    }

    private static byte ReadByte(Stream stream)
    {
        var value = stream.ReadByte();
        if (value < 0)
        {
            throw new EndOfStreamException();
        }

        return (byte)value;
    }

    private static int ReadInt32(Stream stream)
    {
        Span<byte> bytes = stackalloc byte[sizeof(int)];
        stream.ReadExactly(bytes);
        return BinaryPrimitives.ReadInt32LittleEndian(bytes);
    }

    private static uint ReadUInt32(Stream stream)
    {
        Span<byte> bytes = stackalloc byte[sizeof(uint)];
        stream.ReadExactly(bytes);
        return BinaryPrimitives.ReadUInt32LittleEndian(bytes);
    }

    private static long ReadInt64(Stream stream)
    {
        Span<byte> bytes = stackalloc byte[sizeof(long)];
        stream.ReadExactly(bytes);
        return BinaryPrimitives.ReadInt64LittleEndian(bytes);
    }

    private static ulong ReadUInt64(Stream stream)
    {
        Span<byte> bytes = stackalloc byte[sizeof(ulong)];
        stream.ReadExactly(bytes);
        return BinaryPrimitives.ReadUInt64LittleEndian(bytes);
    }
}
