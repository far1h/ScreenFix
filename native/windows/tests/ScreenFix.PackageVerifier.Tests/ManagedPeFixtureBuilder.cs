using System.Buffers.Binary;
using System.Reflection;
using System.Reflection.Metadata;
using System.Reflection.Metadata.Ecma335;
using System.Reflection.PortableExecutable;

namespace ScreenFix.PackageVerifier.Tests;

internal sealed class ManagedPeFixtureBuilder
{
    internal const string IconResourceName =
        "ScreenFix.App.Resources.ScreenFix.ico";

    internal static readonly byte[] IconBytes =
    [
        0x00, 0x00, 0x01, 0x00,
        0x01, 0x00, 0x10, 0x10,
        0x00, 0x00, 0x01, 0x00,
        0x20, 0x00, 0x04, 0x00,
        0x00, 0x00, 0x16, 0x00,
        0x00, 0x00, 0xde, 0xad,
        0xbe, 0xef,
    ];

    internal List<ManagedResourceFixture> Resources { get; } =
    [
        new(IconResourceName, Offset: 0, IsEmbedded: true),
    ];

    internal byte[]? ManagedResourceDirectoryBytes { get; set; }

    internal byte[] Build()
    {
        var metadata = new MetadataBuilder();
        metadata.AddModule(
            generation: 0,
            metadata.GetOrAddString("ScreenFix.dll"),
            metadata.GetOrAddGuid(new Guid("dbb9f3a0-2709-4efc-8acd-c02eb1f21961")),
            default,
            default);
        metadata.AddAssembly(
            metadata.GetOrAddString("ScreenFix"),
            new Version(1, 0, 0, 0),
            default,
            default,
            default,
            AssemblyHashAlgorithm.None);
        foreach (var resource in Resources)
        {
            EntityHandle implementation = default;
            if (!resource.IsEmbedded)
            {
                implementation = metadata.AddAssemblyFile(
                    metadata.GetOrAddString("linked.resources"),
                    default,
                    containsMetadata: false);
            }

            metadata.AddManifestResource(
                ManifestResourceAttributes.Public,
                metadata.GetOrAddString(resource.Name),
                implementation,
                resource.Offset);
        }

        var managedResources = new BlobBuilder();
        if (ManagedResourceDirectoryBytes is null)
        {
            managedResources.WriteInt32(IconBytes.Length);
            managedResources.WriteBytes(IconBytes);
        }
        else
        {
            managedResources.WriteBytes(ManagedResourceDirectoryBytes);
        }

        var peBuilder = new ManagedPEBuilder(
            PEHeaderBuilder.CreateLibraryHeader(),
            new MetadataRootBuilder(metadata),
            new BlobBuilder(),
            managedResources: managedResources);
        var image = new BlobBuilder();
        peBuilder.Serialize(image);
        return image.ToArray();
    }

    internal static void RemoveClrHeader(byte[] image)
    {
        var layout = ReadLayout(image);
        image.AsSpan(layout.CorDirectoryEntryOffset, 8).Clear();
    }

    internal static void RemoveMetadataDirectory(byte[] image)
    {
        var layout = ReadLayout(image);
        image.AsSpan(layout.CorHeaderOffset + 8, 8).Clear();
    }

    internal static void SetManagedResourcesDirectory(
        byte[] image,
        int relativeVirtualAddress,
        int size)
    {
        var layout = ReadLayout(image);
        BinaryPrimitives.WriteInt32LittleEndian(
            image.AsSpan(layout.CorHeaderOffset + 24),
            relativeVirtualAddress);
        BinaryPrimitives.WriteInt32LittleEndian(
            image.AsSpan(layout.CorHeaderOffset + 28),
            size);
    }

    internal static void MakeManagedResourcesDirectoryAmbiguous(byte[] image)
    {
        var layout = ReadLayout(image);
        if (layout.SectionHeaders.Count < 2)
        {
            throw new InvalidOperationException(
                "Fixture needs at least two PE sections.");
        }

        var source = layout.SectionHeaders.Single(section =>
            layout.ResourcesRva >= section.VirtualAddress
            && (long)layout.ResourcesRva + layout.ResourcesSize
                <= (long)section.VirtualAddress + section.SizeOfRawData);
        var target = layout.SectionHeaders.First(section => section != source);
        BinaryPrimitives.WriteInt32LittleEndian(
            image.AsSpan(target.HeaderOffset + 12),
            source.VirtualAddress);
        BinaryPrimitives.WriteInt32LittleEndian(
            image.AsSpan(target.HeaderOffset + 16),
            source.SizeOfRawData);
        BinaryPrimitives.WriteInt32LittleEndian(
            image.AsSpan(target.HeaderOffset + 20),
            source.PointerToRawData);
    }

    internal static void MakeManagedResourcesDirectoryTruncated(byte[] image)
    {
        var layout = ReadLayout(image);
        var section = layout.SectionHeaders.Single(candidate =>
            layout.ResourcesRva >= candidate.VirtualAddress
            && (long)layout.ResourcesRva + layout.ResourcesSize
                <= (long)candidate.VirtualAddress + candidate.SizeOfRawData);
        var relativeOffset = layout.ResourcesRva - section.VirtualAddress;
        var oversizedDirectory = image.Length;
        BinaryPrimitives.WriteInt32LittleEndian(
            image.AsSpan(section.HeaderOffset + 16),
            checked(relativeOffset + oversizedDirectory));
        SetManagedResourcesDirectory(
            image,
            layout.ResourcesRva,
            oversizedDirectory);
    }

    private static ManagedPeLayout ReadLayout(byte[] image)
    {
        var peOffset = BinaryPrimitives.ReadInt32LittleEndian(image.AsSpan(0x3c));
        var coffHeaderOffset = checked(peOffset + 4);
        var sectionCount = BinaryPrimitives.ReadUInt16LittleEndian(
            image.AsSpan(coffHeaderOffset + 2));
        var optionalHeaderSize = BinaryPrimitives.ReadUInt16LittleEndian(
            image.AsSpan(coffHeaderOffset + 16));
        var optionalHeaderOffset = checked(coffHeaderOffset + 20);
        var dataDirectoryOffset = checked(optionalHeaderOffset + 96);
        var corDirectoryEntryOffset = checked(dataDirectoryOffset + (14 * 8));
        var corRva = BinaryPrimitives.ReadInt32LittleEndian(
            image.AsSpan(corDirectoryEntryOffset));
        var sectionHeadersOffset = checked(optionalHeaderOffset + optionalHeaderSize);
        var sections = new List<ManagedPeSection>(sectionCount);
        for (var index = 0; index < sectionCount; index++)
        {
            var headerOffset = checked(sectionHeadersOffset + (index * 40));
            sections.Add(new ManagedPeSection(
                headerOffset,
                BinaryPrimitives.ReadInt32LittleEndian(image.AsSpan(headerOffset + 12)),
                BinaryPrimitives.ReadInt32LittleEndian(image.AsSpan(headerOffset + 16)),
                BinaryPrimitives.ReadInt32LittleEndian(image.AsSpan(headerOffset + 20))));
        }

        var corSection = sections.Single(section =>
            corRva >= section.VirtualAddress
            && corRva < (long)section.VirtualAddress + section.SizeOfRawData);
        var corHeaderOffset = checked(
            corSection.PointerToRawData + corRva - corSection.VirtualAddress);
        var resourcesRva = BinaryPrimitives.ReadInt32LittleEndian(
            image.AsSpan(corHeaderOffset + 24));
        var resourcesSize = BinaryPrimitives.ReadInt32LittleEndian(
            image.AsSpan(corHeaderOffset + 28));
        return new ManagedPeLayout(
            corDirectoryEntryOffset,
            corHeaderOffset,
            resourcesRva,
            resourcesSize,
            sections);
    }

    private sealed record ManagedPeLayout(
        int CorDirectoryEntryOffset,
        int CorHeaderOffset,
        int ResourcesRva,
        int ResourcesSize,
        IReadOnlyList<ManagedPeSection> SectionHeaders);

    private sealed record ManagedPeSection(
        int HeaderOffset,
        int VirtualAddress,
        int SizeOfRawData,
        int PointerToRawData);
}

internal sealed record ManagedResourceFixture(
    string Name,
    uint Offset,
    bool IsEmbedded);
