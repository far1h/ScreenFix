namespace ScreenFix.PackageVerifier.Bundle;

internal enum BundleFileType : byte
{
    Unknown = 0,
    Assembly = 1,
    NativeBinary = 2,
    DepsJson = 3,
    RuntimeConfigJson = 4,
    Symbols = 5,
}

internal sealed class BundleEntry
{
    private BundleEntry(
        long offset,
        long size,
        long compressedSize,
        BundleFileType fileType,
        string relativePath)
    {
        Offset = offset;
        Size = size;
        CompressedSize = compressedSize;
        FileType = fileType;
        RelativePath = relativePath;
    }

    internal static BundleEntry CreateValidated(
        long offset,
        long size,
        long compressedSize,
        BundleFileType fileType,
        string relativePath,
        long manifestOffset)
    {
        ValidateFileType(fileType);
        ValidateRelativePath(relativePath);
        ValidateSpan(
            offset,
            size,
            compressedSize,
            relativePath,
            manifestOffset);
        return new BundleEntry(
            offset,
            size,
            compressedSize,
            fileType,
            relativePath);
    }

    internal long Offset { get; }

    internal long Size { get; }

    internal long CompressedSize { get; }

    internal long StoredSize => CompressedSize > 0 ? CompressedSize : Size;

    internal bool IsCompressed => CompressedSize > 0;

    internal BundleFileType FileType { get; }

    internal string RelativePath { get; }

    private static void ValidateFileType(BundleFileType fileType)
    {
        if (fileType is < BundleFileType.Unknown or > BundleFileType.Symbols)
        {
            throw new InvalidDataException("bundle entry file type is unknown");
        }
    }

    private static void ValidateRelativePath(string path)
    {
        if (path.Length == 0
            || path[0] == '/'
            || path.Contains('\\', StringComparison.Ordinal)
            || HasDrivePrefix(path))
        {
            throw new InvalidDataException(
                "bundle entry path is not a normalized relative path");
        }

        foreach (var segment in path.Split('/'))
        {
            if (segment.Length == 0 || segment is "." or "..")
            {
                throw new InvalidDataException(
                    "bundle entry path is not a normalized relative path");
            }

            if (ChangesUnderWindowsNormalization(segment))
            {
                throw new InvalidDataException(
                    "bundle entry path changes under Windows normalization");
            }
        }
    }

    private static bool ChangesUnderWindowsNormalization(string segment)
    {
        return segment.Contains('\0', StringComparison.Ordinal)
            || segment[^1] is '.' or ' ';
    }

    private static void ValidateSpan(
        long offset,
        long size,
        long compressedSize,
        string relativePath,
        long manifestOffset)
    {
        if (offset <= 0)
        {
            throw new InvalidDataException("bundle entry offset must be positive");
        }

        if (size < 0)
        {
            throw new InvalidDataException("bundle entry declared size is negative");
        }

        if (compressedSize < 0)
        {
            throw new InvalidDataException("bundle entry compressed size is negative");
        }

        var storedSize = compressedSize > 0 ? compressedSize : size;
        if (storedSize == 0)
        {
            throw new InvalidDataException(
                "bundle entry stored span must be positive");
        }

        var end = AddSpan(offset, storedSize);
        if (size > SingleFileBundleReader.MaximumEntryBytes)
        {
            throw new InvalidDataException(
                "bundle entry declared size exceeds 256 MiB");
        }

        if (offset >= manifestOffset)
        {
            throw new InvalidDataException(
                "bundle entry payload must be before the manifest");
        }

        if (end > manifestOffset)
        {
            var rawDiagnostic = relativePath == "ScreenFix.dll"
                && compressedSize == 0
                ? "raw ScreenFix.dll payload is truncated; "
                : string.Empty;
            throw new InvalidDataException(
                $"{rawDiagnostic}bundle entry payload extends into the manifest");
        }
    }

    private static long AddSpan(long offset, long storedSize)
    {
        try
        {
            return checked(offset + storedSize);
        }
        catch (OverflowException exception)
        {
            throw new InvalidDataException("bundle entry span overflows", exception);
        }
    }

    private static bool HasDrivePrefix(string path)
    {
        return path.Length >= 2
            && ((path[0] >= 'A' && path[0] <= 'Z')
                || (path[0] >= 'a' && path[0] <= 'z'))
            && path[1] == ':';
    }
}
