using ScreenFix.PackageVerifier.Bundle;
using System.Diagnostics;
using System.Reflection;

namespace ScreenFix.PackageVerifier.Tests;

[CollectionDefinition(Name, DisableParallelization = true)]
public sealed class StrictCompressionCollection
{
    internal const string Name = "Strict compression switch";
}

[Collection(StrictCompressionCollection.Name)]
public sealed class SingleFileBundleReaderTests : IDisposable
{
    private readonly string _temporaryDirectory;

    public SingleFileBundleReaderTests()
    {
        _temporaryDirectory = Path.Combine(
            Path.GetTempPath(),
            $"screenfix-bundle-reader-tests-{Guid.NewGuid():N}");
        Directory.CreateDirectory(_temporaryDirectory);
    }

    [Fact]
    public void Valid_ReturnsScreenFixAssemblyEntryAndBytes()
    {
        var path = WriteBundle(new BundleFixtureBuilder().Build());

        var result = SingleFileBundleReader.ExtractScreenFixAssembly(
            path,
            BundleCompressionMode.Uncompressed);

        Assert.Equal("ScreenFix.dll", result.Entry.RelativePath);
        Assert.Equal(BundleFileType.Assembly, result.Entry.FileType);
        Assert.Equal(BundleFixtureBuilder.PayloadOffset, result.Entry.Offset);
        Assert.Equal(BundleFixtureBuilder.AssemblyBytes.Length, result.DeclaredSize);
        Assert.Equal(BundleFixtureBuilder.AssemblyBytes.Length, result.StoredSize);
        Assert.False(result.IsCompressed);
        Assert.Equal(BundleFixtureBuilder.AssemblyBytes, result.Bytes);
    }

    [Fact]
    public void EmptyFile_IsRejectedBeforeSignatureScanning()
    {
        var path = WriteBundle([]);

        AssertInvalid(path, "bundle file must be nonempty");
    }

    [Fact]
    public void OversizeFile_IsRejectedBeforeSignatureScanning()
    {
        var path = Path.Combine(_temporaryDirectory, "oversize.exe");
        using (var stream = new FileStream(path, FileMode.CreateNew, FileAccess.Write))
        {
            stream.SetLength(SingleFileBundleReader.MaximumBundleBytes + 1);
        }

        AssertInvalid(path, "bundle file exceeds 512 MiB");
    }

    [Fact]
    public void ManifestHeader_DuplicateSignatureIsRejected()
    {
        AssertInvalid(
            builder => builder.SignatureCount = 2,
            "bundle signature appears more than once");
    }

    [Fact]
    public void ManifestHeader_SignatureScanUsesBufferedReads()
    {
        const int signatureOffset = (200 * 1024) + 17;
        var bytes = CreateSignatureData(256 * 1024, signatureOffset);
        using var stream = new InstrumentedReadStream(bytes);

        var result = SingleFileBundleReader.FindSignature(stream);

        Assert.Equal(signatureOffset, result);
        Assert.Equal(0, stream.ReadByteCallCount);
        Assert.InRange(stream.ReadCallCount, 1, 128);
        Assert.True(stream.MaximumRequestedRead >= 4096);
    }

    [Fact]
    public void ManifestHeader_SignatureSplitAcrossReadBlocksIsFound()
    {
        const int signatureOffset = 10;
        var bytes = CreateSignatureData(96, signatureOffset);
        using var stream = new InstrumentedReadStream(bytes, maximumReadSize: 16);

        var result = SingleFileBundleReader.FindSignature(stream);

        Assert.Equal(signatureOffset, result);
        Assert.Equal(0, stream.ReadByteCallCount);
    }

    [Fact]
    public void ManifestHeader_DuplicateSignaturesAcrossReadBlocksAreRejected()
    {
        var bytes = CreateSignatureData(160, 16, 80);
        using var stream = new InstrumentedReadStream(bytes, maximumReadSize: 32);

        var exception = Assert.Throws<InvalidDataException>(() =>
            SingleFileBundleReader.FindSignature(stream));

        Assert.Contains(
            "bundle signature appears more than once",
            exception.Message,
            StringComparison.Ordinal);
        Assert.Equal(0, stream.ReadByteCallCount);
    }

    [Fact]
    public void ManifestHeader_MissingSignatureIsRejected()
    {
        AssertInvalid(
            builder => builder.SignatureCount = 0,
            "bundle signature is missing");
    }

    [Fact]
    public void ManifestHeader_SignatureWithoutOffsetSlotIsRejected()
    {
        AssertInvalid(
            builder => builder.SignatureOffset = 4,
            "bundle header offset slot is outside the file");
    }

    [Fact]
    public void ManifestHeader_OffsetOutsideFileIsRejected()
    {
        AssertInvalid(
            builder => builder.HeaderOffset = long.MaxValue,
            "bundle header offset is outside the file");
    }

    [Fact]
    public void ManifestHeader_OffsetBeforeSignatureIsRejected()
    {
        AssertInvalid(
            builder => builder.HeaderOffset = 1,
            "bundle header offset precedes the signature");
    }

    [Fact]
    public void ManifestHeader_MajorVersionMismatchIsRejected()
    {
        AssertInvalid(
            builder => builder.MajorVersion = 5,
            "bundle version must be 6.0");
    }

    [Fact]
    public void ManifestHeader_MinorVersionMismatchIsRejected()
    {
        AssertInvalid(
            builder => builder.MinorVersion = 1,
            "bundle version must be 6.0");
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    [InlineData(4097)]
    public void ManifestHeader_EntryCountOutsideRangeIsRejected(int count)
    {
        AssertInvalid(
            builder => builder.EntryCount = count,
            "bundle entry count must be between 1 and 4096");
    }

    [Fact]
    public void ManifestString_MoreThanFiveLengthBytesIsRejected()
    {
        AssertInvalid(
            builder => builder.Entries[0].PathField =
                [0x80, 0x80, 0x80, 0x80, 0x80],
            "seven-bit string length is malformed");
    }

    [Fact]
    public void ManifestString_OverflowingLengthIsRejected()
    {
        AssertInvalid(
            builder => builder.Entries[0].PathField =
                [0xff, 0xff, 0xff, 0xff, 0x08],
            "seven-bit string length overflows");
    }

    [Fact]
    public void ManifestString_NoncanonicalLengthIsRejected()
    {
        AssertInvalid(
            builder => builder.Entries[0].PathField =
            [
                0x8d,
                0x00,
                .. "ScreenFix.dll"u8.ToArray(),
            ],
            "seven-bit string length is noncanonical");
    }

    [Fact]
    public void ManifestString_InvalidUtf8IsRejected()
    {
        AssertInvalid(
            builder => builder.Entries[0].PathField = [0x02, 0xc3, 0x28],
            "manifest string is not valid UTF-8");
    }

    [Theory]
    [InlineData("")]
    [InlineData("/")]
    [InlineData("/ScreenFix.dll")]
    [InlineData("C:/ScreenFix.dll")]
    [InlineData("C:ScreenFix.dll")]
    [InlineData("../ScreenFix.dll")]
    [InlineData("folder/../ScreenFix.dll")]
    [InlineData("./ScreenFix.dll")]
    [InlineData("folder/./ScreenFix.dll")]
    [InlineData("folder\\ScreenFix.dll")]
    [InlineData("folder//ScreenFix.dll")]
    [InlineData("folder/")]
    public void ManifestPath_InvalidRelativePathIsRejected(string relativePath)
    {
        AssertInvalid(
            builder => builder.Entries[0].RelativePath = relativePath,
            "bundle entry path is not a normalized relative path");
    }

    [Theory]
    [InlineData("folder\0name/data.bin")]
    [InlineData("folder./data.bin")]
    [InlineData("folder /data.bin")]
    [InlineData("folder/data.bin.")]
    [InlineData("folder/data.bin ")]
    public void ManifestPath_WindowsNormalizationChangeIsRejected(
        string relativePath)
    {
        AssertInvalid(
            builder =>
            {
                builder.Entries[0].RelativePath = relativePath;
                builder.Entries.Add(new BundleFixtureEntry());
            },
            "bundle entry path changes under Windows normalization");
    }

    [Fact]
    public void ManifestPath_WindowsStableInternalDotsAndSpacesAreAccepted()
    {
        var builder = new BundleFixtureBuilder();
        builder.Entries[0].RelativePath = "folder.with.dot/file name.bin";
        builder.Entries.Add(new BundleFixtureEntry());

        var result = SingleFileBundleReader.ExtractScreenFixAssembly(
            WriteBundle(builder.Build()),
            BundleCompressionMode.Uncompressed);

        Assert.Equal(BundleFixtureBuilder.AssemblyBytes, result.Bytes);
    }

    [Fact]
    public void ManifestPath_OverMaximumUtf8LengthIsRejected()
    {
        AssertInvalid(
            builder => builder.Entries[0].RelativePath = new string('a', 1025),
            "bundle entry path exceeds 1024 UTF-8 bytes");
    }

    [Fact]
    public void ManifestPath_DuplicateOrdinalPathIsRejected()
    {
        AssertInvalid(
            builder => builder.Entries.Add(new BundleFixtureEntry()),
            "bundle entry path is duplicated");
    }

    [Fact]
    public void ManifestPath_UnknownFileTypeIsRejected()
    {
        AssertInvalid(
            builder => builder.Entries[0].FileType = 6,
            "bundle entry file type is unknown");
    }

    [Fact]
    public void ManifestSpan_NegativeOffsetIsRejected()
    {
        AssertInvalid(
            builder => builder.Entries[0].Offset = -1,
            "bundle entry offset must be positive");
    }

    [Fact]
    public void ManifestSpan_OverflowingOffsetIsRejected()
    {
        AssertInvalid(
            builder =>
            {
                builder.Entries[0].Offset = long.MaxValue;
                builder.Entries[0].WritePayload = false;
            },
            "bundle entry span overflows");
    }

    [Fact]
    public void ManifestSpan_NegativeDeclaredSizeIsRejected()
    {
        AssertInvalid(
            builder => builder.Entries[0].Size = -1,
            "bundle entry declared size is negative");
    }

    [Fact]
    public void ManifestSpan_OverflowingDeclaredSizeIsRejected()
    {
        AssertInvalid(
            builder =>
            {
                builder.Entries[0].Size = long.MaxValue;
                builder.Entries[0].WritePayload = false;
            },
            "bundle entry span overflows");
    }

    [Fact]
    public void ManifestSpan_NegativeCompressedSizeIsRejected()
    {
        AssertInvalid(
            builder => builder.Entries[0].CompressedSize = -1,
            "bundle entry compressed size is negative");
    }

    [Fact]
    public void ManifestSpan_OverflowingCompressedSizeIsRejected()
    {
        AssertInvalid(
            builder =>
            {
                builder.Entries[0].CompressedSize = long.MaxValue;
                builder.Entries[0].WritePayload = false;
            },
            "bundle entry span overflows",
            BundleCompressionMode.Compressed);
    }

    [Fact]
    public void ManifestSpan_ZeroStoredSpanIsRejected()
    {
        AssertInvalid(
            builder =>
            {
                builder.Entries[0].Payload = [];
                builder.Entries[0].Size = 0;
            },
            "bundle entry stored span must be positive");
    }

    [Fact]
    public void ManifestSpan_PayloadAtManifestIsRejected()
    {
        AssertInvalid(
            builder =>
            {
                builder.Entries[0].Offset = 256;
                builder.Entries[0].WritePayload = false;
            },
            "bundle entry payload must be before the manifest");
    }

    [Fact]
    public void ManifestSpan_PayloadCrossingManifestIsRejected()
    {
        AssertInvalid(
            builder =>
            {
                builder.Entries[0].Offset = 126;
                builder.Entries[0].WritePayload = false;
            },
            "bundle entry payload extends into the manifest");
    }

    [Fact]
    public void ManifestSpan_OverlappingPayloadsAreRejected()
    {
        AssertInvalid(
            builder =>
            {
                builder.Entries[0].RelativePath = "other.dll";
                builder.Entries.Add(new BundleFixtureEntry { Offset = 130 });
            },
            "bundle entry payload spans overlap");
    }

    [Fact]
    public void ManifestCap_PerEntryDeclaredSizeIsEnforced()
    {
        AssertInvalid(
            builder =>
            {
                builder.Entries[0].RelativePath = "other.dll";
                builder.Entries[0].Payload = [0x01];
                builder.Entries[0].Size = SingleFileBundleReader.MaximumEntryBytes + 1;
                builder.Entries[0].CompressedSize = 1;
                builder.Entries.Add(new BundleFixtureEntry());
            },
            "bundle entry declared size exceeds 256 MiB");
    }

    [Fact]
    public void ManifestCap_CumulativeDeclaredSizeIsEnforced()
    {
        AssertInvalid(
            builder =>
            {
                builder.Entries.Clear();
                builder.Entries.Add(CreateLargeCompressedEntry("one.bin"));
                builder.Entries.Add(CreateLargeCompressedEntry("two.bin"));
                builder.Entries.Add(new BundleFixtureEntry());
            },
            "cumulative bundle entry size exceeds 512 MiB");
    }

    [Fact]
    public void ManifestApp_MissingCaseSensitiveScreenFixAssemblyIsRejected()
    {
        AssertInvalid(
            builder => builder.Entries[0].RelativePath = "screenfix.dll",
            "ScreenFix.dll assembly is missing");
    }

    [Fact]
    public void ManifestApp_DuplicateScreenFixAssemblyIsRejected()
    {
        AssertInvalid(
            builder => builder.Entries.Add(new BundleFixtureEntry()),
            "duplicate ScreenFix.dll");
    }

    [Fact]
    public void ManifestApp_WrongScreenFixFileTypeIsRejected()
    {
        AssertInvalid(
            builder => builder.Entries[0].FileType = 2,
            "ScreenFix.dll must have Assembly file type");
    }

    [Fact]
    public void ManifestApp_ScreenFixDeclaredSizeCapIsEnforced()
    {
        AssertInvalid(
            builder =>
            {
                builder.Entries[0].Payload = [0x01];
                builder.Entries[0].Size =
                    SingleFileBundleReader.MaximumAppAssemblyBytes + 1;
                builder.Entries[0].CompressedSize = 1;
            },
            "ScreenFix.dll declared size exceeds 16 MiB",
            BundleCompressionMode.Compressed);
    }

    [Fact]
    public void ManifestLayout_TruncatedManifestIsRejected()
    {
        AssertInvalid(
            builder => builder.ManifestBytesToRemove = 1,
            "bundle manifest is truncated");
    }

    [Fact]
    public void ManifestLayout_TrailingManifestBytesAreRejected()
    {
        AssertInvalid(
            builder => builder.ManifestSuffix = [0x00],
            "bundle manifest has trailing bytes");
    }

    [Fact]
    public void ManifestFixedHeader_UnknownFlagsAreRejected()
    {
        AssertInvalid(
            builder => builder.Flags = 2,
            "bundle header flags are unknown");
    }

    [Theory]
    [InlineData(1, 0)]
    [InlineData(0, 1)]
    [InlineData(-1, 1)]
    [InlineData(1, -1)]
    public void ManifestFixedHeader_InvalidDepsJsonLocationIsRejected(
        long offset,
        long size)
    {
        AssertInvalid(
            builder =>
            {
                builder.DepsJsonOffset = offset;
                builder.DepsJsonSize = size;
            },
            "bundle deps.json location is invalid");
    }

    [Theory]
    [InlineData(1, 0)]
    [InlineData(0, 1)]
    [InlineData(-1, 1)]
    [InlineData(1, -1)]
    public void ManifestFixedHeader_InvalidRuntimeConfigLocationIsRejected(
        long offset,
        long size)
    {
        AssertInvalid(
            builder =>
            {
                builder.RuntimeConfigJsonOffset = offset;
                builder.RuntimeConfigJsonSize = size;
            },
            "bundle runtimeconfig.json location is invalid");
    }

    [Theory]
    [InlineData(3)]
    [InlineData(4)]
    public void ManifestFixedHeader_MatchingKnownLocationIsAccepted(byte fileType)
    {
        var builder = new BundleFixtureBuilder { Flags = 1 };
        builder.Entries[0].RelativePath = fileType == 3
            ? "ScreenFix.deps.json"
            : "ScreenFix.runtimeconfig.json";
        builder.Entries[0].Payload = [0x01];
        builder.Entries[0].FileType = fileType;
        builder.Entries.Add(new BundleFixtureEntry());
        if (fileType == 3)
        {
            builder.DepsJsonOffset = BundleFixtureBuilder.PayloadOffset;
            builder.DepsJsonSize = 1;
        }
        else
        {
            builder.RuntimeConfigJsonOffset = BundleFixtureBuilder.PayloadOffset;
            builder.RuntimeConfigJsonSize = 1;
        }

        var result = SingleFileBundleReader.ExtractScreenFixAssembly(
            WriteBundle(builder.Build()),
            BundleCompressionMode.Uncompressed);

        Assert.Equal(BundleFixtureBuilder.AssemblyBytes, result.Bytes);
    }

    [Fact]
    public void ManifestFixedHeader_LocationCannotPointToWrongEntryType()
    {
        AssertInvalid(
            builder =>
            {
                builder.DepsJsonOffset = BundleFixtureBuilder.PayloadOffset;
                builder.DepsJsonSize = BundleFixtureBuilder.AssemblyBytes.Length;
            },
            "bundle deps.json location is invalid");
    }

    [Fact]
    public void ManifestFixedHeader_LocationSizeMustMatchTypedEntry()
    {
        AssertInvalid(
            builder =>
            {
                builder.Entries[0].RelativePath = "ScreenFix.deps.json";
                builder.Entries[0].Payload = [0x01];
                builder.Entries[0].FileType = 3;
                builder.Entries.Add(new BundleFixtureEntry());
                builder.DepsJsonOffset = BundleFixtureBuilder.PayloadOffset;
                builder.DepsJsonSize = 2;
            },
            "bundle deps.json location is invalid");
    }

    [Fact]
    public async Task BoundedStream_ReturnsAtMostOneByteForEveryReadShape()
    {
        using var source = new MemoryStream(
            [0x10, 0x20, 0x30, 0x40, 0x50, 0x60]);
        using var bounded = new SingleByteBoundedReadStream(
            source,
            offset: 1,
            length: 4,
            leaveOpen: true);
        var buffer = new byte[8192];

        Assert.Equal(1, bounded.Read(buffer, 0, buffer.Length));
        Assert.Equal(0x20, buffer[0]);
        Assert.Equal(1, bounded.Read(buffer.AsSpan()));
        Assert.Equal(0x30, buffer[0]);
        Assert.Equal(1, await bounded.ReadAsync(buffer, 0, buffer.Length));
        Assert.Equal(0x40, buffer[0]);
        Assert.Equal(1, await bounded.ReadAsync(buffer.AsMemory()));
        Assert.Equal(0x50, buffer[0]);
        Assert.Equal(4, bounded.Consumed);
        Assert.Equal(0, bounded.Remaining);
        Assert.Equal(0, bounded.Read(buffer, 0, buffer.Length));
    }

    [Fact]
    public void BoundedStream_PreventsSeekingAndWriting()
    {
        using var source = new MemoryStream([0x01]);
        using var bounded = new SingleByteBoundedReadStream(
            source,
            offset: 0,
            length: 1,
            leaveOpen: true);

        Assert.True(bounded.CanRead);
        Assert.False(bounded.CanSeek);
        Assert.False(bounded.CanWrite);
        Assert.Throws<NotSupportedException>(() => { _ = bounded.Length; });
        Assert.Throws<NotSupportedException>(() => { _ = bounded.Position; });
        Assert.Throws<NotSupportedException>(() => { bounded.Position = 0; });
        Assert.Throws<NotSupportedException>(() =>
        {
            bounded.Seek(0, SeekOrigin.Begin);
        });
        Assert.Throws<NotSupportedException>(() => { bounded.SetLength(0); });
        Assert.Throws<NotSupportedException>(() =>
        {
            bounded.Write([0x01], 0, 1);
        });
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public void BoundedStream_DisposesSourceOnlyWhenOwned(bool leaveOpen)
    {
        var source = new MemoryStream([0x01]);
        var bounded = new SingleByteBoundedReadStream(
            source,
            offset: 0,
            length: 1,
            leaveOpen);

        bounded.Dispose();

        if (leaveOpen)
        {
            Assert.Equal(0x01, source.ReadByte());
            source.Dispose();
        }
        else
        {
            Assert.Throws<ObjectDisposedException>(() => source.ReadByte());
        }
    }

    [Fact]
    public void Compression_ValidCompressedAssemblyIsExtracted()
    {
        var path = WriteCompressedBundle(
            BundleFixtureBuilder.CreateStoredDeflate(
                BundleFixtureBuilder.AssemblyBytes));

        var result = SingleFileBundleReader.ExtractScreenFixAssembly(
            path,
            BundleCompressionMode.Compressed);

        Assert.True(result.IsCompressed);
        Assert.Equal(BundleFixtureBuilder.AssemblyBytes.Length, result.DeclaredSize);
        Assert.Equal(9, result.StoredSize);
        Assert.Equal(BundleFixtureBuilder.AssemblyBytes, result.Bytes);
    }

    [Fact]
    public void Compression_CompressedEntryInUncompressedModeIsRejected()
    {
        AssertInvalid(
            builder => ConfigureCompressedEntry(
                builder.Entries[0],
                BundleFixtureBuilder.CreateStoredDeflate(
                    BundleFixtureBuilder.AssemblyBytes)),
            "expected uncompressed ScreenFix.dll but CompressedSize is positive");
    }

    [Fact]
    public void Compression_RawEntryInCompressedModeIsRejected()
    {
        AssertInvalid(
            _ => { },
            "expected compressed ScreenFix.dll but CompressedSize is zero",
            BundleCompressionMode.Compressed);
    }

    [Fact]
    public void Compression_StrictSwitchDisabledIsRejectedBeforeDeflateCreation()
    {
        var path = WriteCompressedBundle(
            BundleFixtureBuilder.CreateStoredDeflate(
                BundleFixtureBuilder.AssemblyBytes));
        AppContext.SetSwitch("System.IO.Compression.UseStrictValidation", false);

        try
        {
            var exception = Assert.Throws<InvalidDataException>(() =>
                SingleFileBundleReader.ExtractScreenFixAssembly(
                    path,
                    BundleCompressionMode.Compressed));
            Assert.Contains(
                "strict deflate validation is not enabled",
                exception.Message,
                StringComparison.Ordinal);
        }
        finally
        {
            AppContext.SetSwitch("System.IO.Compression.UseStrictValidation", true);
        }
    }

    [Fact]
    public void Compression_StrictSwitchMutationIsInNonparallelCollection()
    {
        const string collectionName = "Strict compression switch";
        var testClassCollection = Assert.Single(
            CustomAttributeData.GetCustomAttributes(
                typeof(SingleFileBundleReaderTests)),
            attribute => attribute.AttributeType == typeof(CollectionAttribute));
        Assert.Equal(
            collectionName,
            Assert.Single(testClassCollection.ConstructorArguments).Value);

        var definition = Assert.Single(
            typeof(SingleFileBundleReaderTests).Assembly.GetTypes()
                .SelectMany(type => CustomAttributeData.GetCustomAttributes(type)),
            attribute =>
                attribute.AttributeType == typeof(CollectionDefinitionAttribute)
                && Equals(
                    Assert.Single(attribute.ConstructorArguments).Value,
                    collectionName));
        var parallelization = Assert.Single(
            definition.NamedArguments,
            argument => argument.MemberName == "DisableParallelization");
        Assert.Equal(true, parallelization.TypedValue.Value);
    }

    [Fact]
    public void Compression_CorruptDeflateIsRejected()
    {
        AssertInvalidCompressed(
            [0x07, 0xff, 0xff, 0xff],
            BundleFixtureBuilder.AssemblyBytes.Length,
            "compressed ScreenFix.dll payload is corrupt");
    }

    [Fact]
    public void Compression_TruncatedDeflateIsRejected()
    {
        var compressed = BundleFixtureBuilder.CreateStoredDeflate(
            BundleFixtureBuilder.AssemblyBytes);
        Array.Resize(ref compressed, compressed.Length - 1);

        AssertInvalidCompressed(
            compressed,
            BundleFixtureBuilder.AssemblyBytes.Length,
            "compressed ScreenFix.dll payload is truncated");
    }

    [Fact]
    public void Compression_ExactOutputWithoutFinalBlockIsRejected()
    {
        AssertInvalidCompressed(
            BundleFixtureBuilder.CreateStoredDeflate(
                BundleFixtureBuilder.AssemblyBytes,
                isFinalBlock: false),
            BundleFixtureBuilder.AssemblyBytes.Length,
            "compressed ScreenFix.dll payload is not cleanly terminated");
    }

    [Fact]
    public void Compression_DeclaredOutputLongerThanActualIsRejected()
    {
        AssertInvalidCompressed(
            BundleFixtureBuilder.CreateStoredDeflate([0x01, 0x02, 0x03]),
            declaredSize: 4,
            "decompressed ScreenFix.dll is shorter than declared size");
    }

    [Fact]
    public void Compression_DeclaredOutputShorterThanActualIsRejected()
    {
        AssertInvalidCompressed(
            BundleFixtureBuilder.CreateStoredDeflate(
                BundleFixtureBuilder.AssemblyBytes),
            declaredSize: 3,
            "decompressed ScreenFix.dll exceeds declared size");
    }

    [Fact]
    public void Compression_AppendedBytesAreRejected()
    {
        AssertInvalidCompressed(
            [
                .. BundleFixtureBuilder.CreateStoredDeflate(
                    BundleFixtureBuilder.AssemblyBytes),
                0xde,
                0xad,
            ],
            BundleFixtureBuilder.AssemblyBytes.Length,
            "compressed ScreenFix.dll payload has trailing bytes");
    }

    [Fact]
    public void Compression_IncompleteDeclaredSpanIsRejected()
    {
        AssertInvalidCompressed(
            [
                .. BundleFixtureBuilder.CreateStoredDeflate(
                    BundleFixtureBuilder.AssemblyBytes),
                0x00,
            ],
            BundleFixtureBuilder.AssemblyBytes.Length,
            "compressed ScreenFix.dll span was not fully consumed");
    }

    [Fact]
    public void Raw_TruncatedDeclaredSpanIsRejectedDistinctly()
    {
        AssertInvalid(
            builder =>
            {
                builder.Entries[0].Offset = 126;
                builder.Entries[0].WritePayload = false;
            },
            "raw ScreenFix.dll payload is truncated");
    }

    [Fact]
    public async Task FreshProcess_EnablesStrictValidationForValidCompressedBundle()
    {
        var assembly = new ManagedPeFixtureBuilder().Build();
        var compressed = BundleFixtureBuilder.CreateStoredDeflate(assembly);
        var path = WriteCompressedBundle(compressed, assembly.LongLength);

        var result = await RunVerifierProcess(path, "compressed");

        Assert.Equal(0, result.ExitCode);
        Assert.Equal(
            $"verified mode=compressed executable-bytes={new FileInfo(path).Length} "
                + $"managed-declared-bytes={assembly.LongLength} "
                + $"managed-stored-bytes={compressed.LongLength} "
                + $"icon-bytes={ManagedPeFixtureBuilder.IconBytes.Length}"
                + Environment.NewLine,
            result.Output);
        Assert.Empty(result.Error);
    }

    [Fact]
    public async Task FreshProcess_RejectsExactOutputWithoutFinalDeflateBlock()
    {
        var path = WriteCompressedBundle(
            BundleFixtureBuilder.CreateStoredDeflate(
                BundleFixtureBuilder.AssemblyBytes,
                isFinalBlock: false));

        var result = await RunVerifierProcess(path, "compressed");

        Assert.Equal(1, result.ExitCode);
        Assert.Contains(
            "compressed ScreenFix.dll payload is not cleanly terminated",
            result.Error,
            StringComparison.Ordinal);
    }

    public void Dispose()
    {
        Directory.Delete(_temporaryDirectory, recursive: true);
    }

    private string WriteBundle(byte[] bytes)
    {
        var path = Path.Combine(_temporaryDirectory, "ScreenFix.exe");
        File.WriteAllBytes(path, bytes);
        return path;
    }

    private string WriteCompressedBundle(byte[] compressed, long? declaredSize = null)
    {
        var builder = new BundleFixtureBuilder();
        ConfigureCompressedEntry(builder.Entries[0], compressed, declaredSize);
        return WriteBundle(builder.Build());
    }

    private static void AssertInvalid(string path, string diagnosticFragment)
    {
        var exception = Assert.Throws<InvalidDataException>(() =>
            SingleFileBundleReader.ExtractScreenFixAssembly(
                path,
                BundleCompressionMode.Uncompressed));

        Assert.Contains(diagnosticFragment, exception.Message, StringComparison.Ordinal);
    }

    private void AssertInvalid(
        Action<BundleFixtureBuilder> configure,
        string diagnosticFragment,
        BundleCompressionMode mode = BundleCompressionMode.Uncompressed)
    {
        var builder = new BundleFixtureBuilder();
        configure(builder);
        var path = WriteBundle(builder.Build());
        var exception = Assert.Throws<InvalidDataException>(() =>
            SingleFileBundleReader.ExtractScreenFixAssembly(path, mode));

        Assert.Contains(diagnosticFragment, exception.Message, StringComparison.Ordinal);
    }

    private static BundleFixtureEntry CreateLargeCompressedEntry(string path)
    {
        return new BundleFixtureEntry
        {
            RelativePath = path,
            Payload = [0x01],
            Size = SingleFileBundleReader.MaximumEntryBytes,
            CompressedSize = 1,
            FileType = 0,
        };
    }

    private void AssertInvalidCompressed(
        byte[] compressed,
        long declaredSize,
        string diagnosticFragment)
    {
        var path = WriteCompressedBundle(compressed, declaredSize);
        var exception = Assert.Throws<InvalidDataException>(() =>
            SingleFileBundleReader.ExtractScreenFixAssembly(
                path,
                BundleCompressionMode.Compressed));

        Assert.Contains(diagnosticFragment, exception.Message, StringComparison.Ordinal);
    }

    private static void ConfigureCompressedEntry(
        BundleFixtureEntry entry,
        byte[] compressed,
        long? declaredSize = null)
    {
        entry.Payload = compressed;
        entry.Size = declaredSize ?? BundleFixtureBuilder.AssemblyBytes.Length;
        entry.CompressedSize = compressed.LongLength;
    }

    private static byte[] CreateSignatureData(
        int length,
        params int[] signatureOffsets)
    {
        var bytes = new byte[length];
        foreach (var signatureOffset in signatureOffsets)
        {
            BundleFixtureBuilder.Signature.CopyTo(bytes, signatureOffset);
        }

        return bytes;
    }

    private async Task<ProcessResult> RunVerifierProcess(
        string executable,
        string compressionMode)
    {
        var canonicalIcon = Path.Combine(_temporaryDirectory, "ScreenFix.ico");
        await File.WriteAllBytesAsync(
            canonicalIcon,
            ManagedPeFixtureBuilder.IconBytes);
        var fileName = OperatingSystem.IsWindows()
            ? "ScreenFix.PackageVerifier.exe"
            : "ScreenFix.PackageVerifier";
        var verifier = Path.Combine(
            Path.GetDirectoryName(typeof(Program).Assembly.Location)!,
            fileName);
        var startInfo = new ProcessStartInfo
        {
            FileName = verifier,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            WorkingDirectory = _temporaryDirectory,
        };
        startInfo.ArgumentList.Add("--executable");
        startInfo.ArgumentList.Add(executable);
        startInfo.ArgumentList.Add("--canonical-icon");
        startInfo.ArgumentList.Add(canonicalIcon);
        startInfo.ArgumentList.Add("--compression");
        startInfo.ArgumentList.Add(compressionMode);

        using var process = Process.Start(startInfo)
            ?? throw new InvalidOperationException("Unable to start verifier process.");
        var outputTask = process.StandardOutput.ReadToEndAsync();
        var errorTask = process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync();
        return new ProcessResult(
            process.ExitCode,
            await outputTask,
            await errorTask);
    }

    private sealed record ProcessResult(int ExitCode, string Output, string Error);

    private sealed class InstrumentedReadStream(
        byte[] bytes,
        int maximumReadSize = int.MaxValue) : MemoryStream(bytes, writable: false)
    {
        internal int ReadByteCallCount { get; private set; }

        internal int ReadCallCount { get; private set; }

        internal int MaximumRequestedRead { get; private set; }

        public override int Read(byte[] buffer, int offset, int count)
        {
            RecordRead(count);
            return base.Read(
                buffer,
                offset,
                Math.Min(count, maximumReadSize));
        }

        public override int Read(Span<byte> buffer)
        {
            RecordRead(buffer.Length);
            return base.Read(buffer[..Math.Min(buffer.Length, maximumReadSize)]);
        }

        public override int ReadByte()
        {
            ReadByteCallCount++;
            return base.ReadByte();
        }

        private void RecordRead(int requestedCount)
        {
            ReadCallCount++;
            MaximumRequestedRead = Math.Max(MaximumRequestedRead, requestedCount);
        }
    }
}
