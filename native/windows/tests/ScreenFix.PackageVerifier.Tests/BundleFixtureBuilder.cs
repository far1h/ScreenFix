using System.Text;
using System.Runtime.CompilerServices;

namespace ScreenFix.PackageVerifier.Tests;

internal sealed class BundleFixtureBuilder
{
    internal const long PayloadOffset = 128;

    internal static readonly byte[] Signature =
    [
        0x8b, 0x12, 0x02, 0xb9, 0x6a, 0x61, 0x20, 0x38,
        0x72, 0x7b, 0x93, 0x02, 0x14, 0xd7, 0xa0, 0x32,
        0x13, 0xf5, 0xb9, 0xe6, 0xef, 0xae, 0x33, 0x18,
        0xee, 0x3b, 0x2d, 0xce, 0x24, 0xb3, 0x6a, 0xae,
    ];

    internal static readonly byte[] AssemblyBytes = [0x01, 0x23, 0x45, 0x67];

    internal BundleFixtureBuilder()
    {
        Entries.Add(new BundleFixtureEntry());
    }

    internal uint MajorVersion { get; set; } = 6;

    internal uint MinorVersion { get; set; }

    internal int? EntryCount { get; set; }

    internal int SignatureCount { get; set; } = 1;

    internal int SignatureOffset { get; set; } = 32;

    internal long? HeaderOffset { get; set; }

    internal byte[]? BundleIdField { get; set; }

    internal long DepsJsonOffset { get; set; }

    internal long DepsJsonSize { get; set; }

    internal long RuntimeConfigJsonOffset { get; set; }

    internal long RuntimeConfigJsonSize { get; set; }

    internal ulong Flags { get; set; }

    internal byte[] ManifestSuffix { get; set; } = [];

    internal int ManifestBytesToRemove { get; set; }

    internal List<BundleFixtureEntry> Entries { get; } = [];

    internal long LastManifestOffset { get; private set; }

    internal byte[] Build()
    {
        using var stream = new MemoryStream();
        stream.SetLength(PayloadOffset);
        WriteSignatures(stream);
        WritePayloads(stream);

        LastManifestOffset = stream.Length;
        stream.Position = LastManifestOffset;
        using var writer = new BinaryWriter(stream, new UTF8Encoding(false), leaveOpen: true);
        writer.Write(MajorVersion);
        writer.Write(MinorVersion);
        writer.Write(EntryCount ?? Entries.Count);
        WriteStringField(writer, BundleIdField, Encoding.UTF8.GetBytes("fixture-id"));
        writer.Write(DepsJsonOffset);
        writer.Write(DepsJsonSize);
        writer.Write(RuntimeConfigJsonOffset);
        writer.Write(RuntimeConfigJsonSize);
        writer.Write(Flags);

        foreach (var entry in Entries)
        {
            writer.Write(entry.ActualOffset);
            writer.Write(entry.Size ?? entry.Payload.LongLength);
            writer.Write(entry.CompressedSize);
            writer.Write(entry.FileType);
            WriteStringField(writer, entry.PathField, Encoding.UTF8.GetBytes(entry.RelativePath));
        }

        writer.Write(ManifestSuffix);
        writer.Flush();
        WriteHeaderOffsets(stream);

        var bytes = stream.ToArray();
        if (ManifestBytesToRemove > 0)
        {
            Array.Resize(ref bytes, bytes.Length - ManifestBytesToRemove);
        }

        return bytes;
    }

    internal static byte[] EncodeStringField(byte[] bytes)
    {
        using var stream = new MemoryStream();
        using var writer = new BinaryWriter(stream, Encoding.UTF8, leaveOpen: true);
        Write7BitEncodedInt(writer, bytes.Length);
        writer.Write(bytes);
        writer.Flush();
        return stream.ToArray();
    }

    internal static byte[] CreateStoredDeflate(
        byte[] bytes,
        bool isFinalBlock = true)
    {
        if (bytes.Length > ushort.MaxValue)
        {
            throw new ArgumentOutOfRangeException(nameof(bytes));
        }

        var length = (ushort)bytes.Length;
        var complement = (ushort)~length;
        return
        [
            isFinalBlock ? (byte)0x01 : (byte)0x00,
            (byte)length,
            (byte)(length >> 8),
            (byte)complement,
            (byte)(complement >> 8),
            .. bytes,
        ];
    }

    private void WriteSignatures(Stream stream)
    {
        for (var index = 0; index < SignatureCount; index++)
        {
            stream.Position = SignatureOffset + (index * 48);
            stream.Write(Signature);
        }
    }

    private void WritePayloads(Stream stream)
    {
        var nextOffset = PayloadOffset;
        foreach (var entry in Entries)
        {
            entry.ActualOffset = entry.Offset ?? nextOffset;
            if (entry.WritePayload && entry.ActualOffset >= 0)
            {
                stream.Position = entry.ActualOffset;
                stream.Write(entry.Payload);
                nextOffset = Math.Max(nextOffset, stream.Position);
            }
        }
    }

    private void WriteHeaderOffsets(Stream stream)
    {
        Span<byte> value = stackalloc byte[sizeof(long)];
        System.Buffers.Binary.BinaryPrimitives.WriteInt64LittleEndian(
            value,
            HeaderOffset ?? LastManifestOffset);
        for (var index = 0; index < SignatureCount; index++)
        {
            var signatureOffset = SignatureOffset + (index * 48);
            if (signatureOffset < sizeof(long))
            {
                continue;
            }

            stream.Position = signatureOffset - sizeof(long);
            stream.Write(value);
        }
    }

    private static void WriteStringField(
        BinaryWriter writer,
        byte[]? encodedField,
        byte[] defaultBytes)
    {
        writer.Write(encodedField ?? EncodeStringField(defaultBytes));
    }

    private static void Write7BitEncodedInt(BinaryWriter writer, int value)
    {
        var remaining = (uint)value;
        while (remaining >= 0x80)
        {
            writer.Write((byte)(remaining | 0x80));
            remaining >>= 7;
        }

        writer.Write((byte)remaining);
    }
}

internal static class BundleTestModuleInitializer
{
    [ModuleInitializer]
    internal static void EnableStrictDeflateValidation()
    {
        AppContext.SetSwitch("System.IO.Compression.UseStrictValidation", true);
        if (!AppContext.TryGetSwitch(
                "System.IO.Compression.UseStrictValidation",
                out var isEnabled)
            || !isEnabled)
        {
            throw new InvalidOperationException(
                "Strict deflate validation could not be enabled for the test process.");
        }
    }
}

internal sealed class BundleFixtureEntry
{
    internal string RelativePath { get; set; } = "ScreenFix.dll";

    internal byte[]? PathField { get; set; }

    internal byte[] Payload { get; set; } = BundleFixtureBuilder.AssemblyBytes;

    internal long? Offset { get; set; }

    internal long? Size { get; set; }

    internal long CompressedSize { get; set; }

    internal byte FileType { get; set; } = 1;

    internal bool WritePayload { get; set; } = true;

    internal long ActualOffset { get; set; }
}
