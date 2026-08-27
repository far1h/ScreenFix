using System.Buffers.Binary;
using System.Reflection.Metadata;
using System.Reflection.PortableExecutable;

namespace ScreenFix.PackageVerifier.Resources;

internal static class ManagedIconResourceReader
{
    internal const string ResourceName =
        "ScreenFix.App.Resources.ScreenFix.ico";

    internal static byte[] ReadScreenFixIcon(byte[] assemblyBytes)
    {
        ArgumentNullException.ThrowIfNull(assemblyBytes);

        try
        {
            using var stream = new MemoryStream(assemblyBytes, writable: false);
            using var peReader = new PEReader(stream);
            var headers = peReader.PEHeaders;
            if (headers.PEHeader is null)
            {
                throw new InvalidDataException("managed assembly is not a valid PE image");
            }

            if (headers.CorHeader is null)
            {
                throw new InvalidDataException("managed assembly CLR header is missing");
            }

            if (!peReader.HasMetadata)
            {
                throw new InvalidDataException("managed assembly metadata is missing");
            }

            var directory = headers.CorHeader.ResourcesDirectory;
            if (directory.RelativeVirtualAddress <= 0 || directory.Size <= 0)
            {
                throw new InvalidDataException(
                    "managed resources directory is missing or empty");
            }

            var resourceDirectoryOffset = MapResourceDirectory(
                headers,
                directory,
                assemblyBytes.LongLength);
            var metadata = peReader.GetMetadataReader();
            var matchingResources = metadata.ManifestResources
                .Select(metadata.GetManifestResource)
                .Where(resource =>
                    string.Equals(
                        metadata.GetString(resource.Name),
                        ResourceName,
                        StringComparison.Ordinal))
                .ToArray();
            if (matchingResources.Length == 0)
            {
                throw new InvalidDataException(
                    $"managed resource {ResourceName} is missing");
            }

            if (matchingResources.Length > 1)
            {
                throw new InvalidDataException(
                    $"managed resource {ResourceName} is duplicated");
            }

            var resource = matchingResources[0];
            if (!resource.Implementation.IsNil)
            {
                throw new InvalidDataException(
                    $"managed resource {ResourceName} is linked, not embedded");
            }

            return ReadResourcePayload(
                assemblyBytes,
                resourceDirectoryOffset,
                directory.Size,
                resource.Offset);
        }
        catch (BadImageFormatException exception)
        {
            throw new InvalidDataException("managed assembly is not a valid PE image", exception);
        }
    }

    private static long MapResourceDirectory(
        PEHeaders headers,
        DirectoryEntry directory,
        long fileLength)
    {
        try
        {
            _ = checked(
                directory.RelativeVirtualAddress + directory.Size);
        }
        catch (OverflowException exception)
        {
            throw new InvalidDataException(
                "managed resources directory range overflows",
                exception);
        }

        var matches = new List<long>();
        var truncatedMatch = false;
        foreach (var section in headers.SectionHeaders)
        {
            try
            {
                var relativeOffset = checked(
                    (long)directory.RelativeVirtualAddress - section.VirtualAddress);
                var directoryEnd = checked(relativeOffset + directory.Size);
                if (relativeOffset < 0 || directoryEnd > section.SizeOfRawData)
                {
                    continue;
                }

                var fileOffset = checked((long)section.PointerToRawData + relativeOffset);
                var fileEnd = checked(fileOffset + directory.Size);
                if (fileOffset < 0 || fileEnd > fileLength)
                {
                    truncatedMatch = true;
                    continue;
                }

                matches.Add(fileOffset);
            }
            catch (OverflowException)
            {
                throw new InvalidDataException(
                    "managed resources directory mapping overflows");
            }
        }

        if (matches.Count == 0 && truncatedMatch)
        {
            throw new InvalidDataException(
                "managed resources directory is truncated in the PE file");
        }

        return matches.Count switch
        {
            0 => throw new InvalidDataException(
                "managed resources directory is outside PE section raw data"),
            1 => matches[0],
            _ => throw new InvalidDataException(
                "managed resources directory maps to multiple PE sections"),
        };
    }

    private static byte[] ReadResourcePayload(
        byte[] assemblyBytes,
        long directoryOffset,
        int directorySize,
        long resourceOffset)
    {
        if (resourceOffset < 0
            || resourceOffset > uint.MaxValue - (uint)sizeof(int))
        {
            throw new InvalidDataException("managed resource offset overflows");
        }

        long prefixOffset;
        long directoryEnd;
        try
        {
            prefixOffset = checked(directoryOffset + resourceOffset);
            directoryEnd = checked(directoryOffset + directorySize);
        }
        catch (OverflowException exception)
        {
            throw new InvalidDataException("managed resource offset overflows", exception);
        }

        long payloadOffset;
        try
        {
            payloadOffset = checked(prefixOffset + sizeof(int));
        }
        catch (OverflowException exception)
        {
            throw new InvalidDataException("managed resource offset overflows", exception);
        }

        if (prefixOffset < directoryOffset || payloadOffset > directoryEnd)
        {
            throw new InvalidDataException(
                "managed resource length prefix is outside the resources directory");
        }

        var payloadLength = BinaryPrimitives.ReadInt32LittleEndian(
            assemblyBytes.AsSpan(checked((int)prefixOffset), sizeof(int)));
        if (payloadLength < 0)
        {
            throw new InvalidDataException("managed resource length is invalid");
        }

        long payloadEnd;
        try
        {
            payloadEnd = checked(payloadOffset + payloadLength);
        }
        catch (OverflowException exception)
        {
            throw new InvalidDataException("managed resource payload length overflows", exception);
        }

        if (payloadEnd > directoryEnd)
        {
            throw new InvalidDataException(
                "managed resource payload extends outside the resources directory");
        }

        return assemblyBytes
            .AsSpan(checked((int)payloadOffset), payloadLength)
            .ToArray();
    }
}
