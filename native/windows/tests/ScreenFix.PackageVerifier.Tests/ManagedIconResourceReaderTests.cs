using ScreenFix.PackageVerifier.Resources;

namespace ScreenFix.PackageVerifier.Tests;

public sealed class ManagedIconResourceReaderTests
{
    [Fact]
    public void FixtureBuilder_ProducesDeterministicImage()
    {
        var first = new ManagedPeFixtureBuilder().Build();
        var second = new ManagedPeFixtureBuilder().Build();

        Assert.Equal(first, second);
    }

    [Fact]
    public void Valid_ReturnsEmbeddedIconBytes()
    {
        var assembly = new ManagedPeFixtureBuilder().Build();

        var result = ManagedIconResourceReader.ReadScreenFixIcon(assembly);

        Assert.Equal(ManagedPeFixtureBuilder.IconBytes, result);
    }

    [Fact]
    public void InvalidPe_IsRejected()
    {
        AssertInvalid(new byte[128], "managed assembly is not a valid PE image");
    }

    [Fact]
    public void MissingClrHeader_IsRejected()
    {
        var assembly = new ManagedPeFixtureBuilder().Build();
        ManagedPeFixtureBuilder.RemoveClrHeader(assembly);

        AssertInvalid(assembly, "managed assembly CLR header is missing");
    }

    [Fact]
    public void ZeroMetadataDirectory_IsRejectedAsInvalidPe()
    {
        var assembly = new ManagedPeFixtureBuilder().Build();
        ManagedPeFixtureBuilder.RemoveMetadataDirectory(assembly);

        AssertInvalid(assembly, "managed assembly is not a valid PE image");
    }

    [Fact]
    public void ZeroResourceDirectory_IsRejected()
    {
        var assembly = new ManagedPeFixtureBuilder().Build();
        ManagedPeFixtureBuilder.SetManagedResourcesDirectory(assembly, 0, 0);

        AssertInvalid(assembly, "managed resources directory is missing or empty");
    }

    [Fact]
    public void ResourceDirectoryOutsideSections_IsRejected()
    {
        var assembly = new ManagedPeFixtureBuilder().Build();
        ManagedPeFixtureBuilder.SetManagedResourcesDirectory(
            assembly,
            0x70000000,
            16);

        AssertInvalid(
            assembly,
            "managed resources directory is outside PE section raw data");
    }

    [Fact]
    public void ResourceDirectoryMappedByMultipleSections_IsRejected()
    {
        var assembly = new ManagedPeFixtureBuilder().Build();
        ManagedPeFixtureBuilder.MakeManagedResourcesDirectoryAmbiguous(assembly);

        AssertInvalid(
            assembly,
            "managed resources directory maps to multiple PE sections");
    }

    [Fact]
    public void OverflowingResourceDirectoryRange_IsRejected()
    {
        var assembly = new ManagedPeFixtureBuilder().Build();
        ManagedPeFixtureBuilder.SetManagedResourcesDirectory(
            assembly,
            int.MaxValue - 1,
            16);

        AssertInvalid(
            assembly,
            "managed resources directory range overflows");
    }

    [Fact]
    public void TruncatedResourceDirectory_IsRejected()
    {
        var assembly = new ManagedPeFixtureBuilder().Build();
        ManagedPeFixtureBuilder.MakeManagedResourcesDirectoryTruncated(assembly);

        AssertInvalid(
            assembly,
            "managed resources directory is truncated in the PE file");
    }

    [Fact]
    public void MissingStableResourceName_IsRejected()
    {
        var builder = new ManagedPeFixtureBuilder();
        builder.Resources[0] = new ManagedResourceFixture(
            "ScreenFix.App.Resources.Other.ico",
            Offset: 0,
            IsEmbedded: true);

        AssertInvalid(
            builder.Build(),
            $"managed resource {ManagedPeFixtureBuilder.IconResourceName} is missing");
    }

    [Fact]
    public void CaseMismatchedStableResourceName_IsRejectedAsMissing()
    {
        var builder = new ManagedPeFixtureBuilder();
        builder.Resources[0] = new ManagedResourceFixture(
            "screenfix.app.resources.screenfix.ico",
            Offset: 0,
            IsEmbedded: true);

        AssertInvalid(
            builder.Build(),
            $"managed resource {ManagedPeFixtureBuilder.IconResourceName} is missing");
    }

    [Fact]
    public void DuplicateStableResourceName_IsRejected()
    {
        var builder = new ManagedPeFixtureBuilder();
        builder.Resources.Add(new ManagedResourceFixture(
            ManagedPeFixtureBuilder.IconResourceName,
            Offset: 0,
            IsEmbedded: true));

        AssertInvalid(
            builder.Build(),
            $"managed resource {ManagedPeFixtureBuilder.IconResourceName} is duplicated");
    }

    [Fact]
    public void LinkedStableResource_IsRejected()
    {
        var builder = new ManagedPeFixtureBuilder();
        builder.Resources[0] = new ManagedResourceFixture(
            ManagedPeFixtureBuilder.IconResourceName,
            Offset: 0,
            IsEmbedded: false);

        AssertInvalid(
            builder.Build(),
            $"managed resource {ManagedPeFixtureBuilder.IconResourceName} is linked, not embedded");
    }

    [Fact]
    public void OverflowingResourceOffset_IsRejected()
    {
        var builder = new ManagedPeFixtureBuilder();
        builder.Resources[0] = new ManagedResourceFixture(
            ManagedPeFixtureBuilder.IconResourceName,
            uint.MaxValue,
            IsEmbedded: true);

        AssertInvalid(builder.Build(), "managed resource offset overflows");
    }

    [Fact]
    public void ResourceOffsetOutsideDirectory_IsRejected()
    {
        var builder = new ManagedPeFixtureBuilder();
        builder.Resources[0] = new ManagedResourceFixture(
            ManagedPeFixtureBuilder.IconResourceName,
            checked((uint)(sizeof(int) + ManagedPeFixtureBuilder.IconBytes.Length)),
            IsEmbedded: true);

        AssertInvalid(
            builder.Build(),
            "managed resource length prefix is outside the resources directory");
    }

    [Fact]
    public void TruncatedResourceLengthPrefix_IsRejected()
    {
        var builder = new ManagedPeFixtureBuilder
        {
            ManagedResourceDirectoryBytes = [0x01, 0x02, 0x03],
        };

        AssertInvalid(
            builder.Build(),
            "managed resource length prefix is outside the resources directory");
    }

    [Fact]
    public void DeclaredPayloadOutsideDirectory_IsRejected()
    {
        var builder = new ManagedPeFixtureBuilder
        {
            ManagedResourceDirectoryBytes = [0x64, 0x00, 0x00, 0x00, 0x01],
        };

        AssertInvalid(
            builder.Build(),
            "managed resource payload extends outside the resources directory");
    }

    private static void AssertInvalid(byte[] assembly, string diagnostic)
    {
        var exception = Assert.Throws<InvalidDataException>(() =>
            ManagedIconResourceReader.ReadScreenFixIcon(assembly));

        Assert.Contains(diagnostic, exception.Message, StringComparison.Ordinal);
    }
}
