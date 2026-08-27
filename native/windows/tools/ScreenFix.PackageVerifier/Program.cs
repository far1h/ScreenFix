using ScreenFix.PackageVerifier.Bundle;

namespace ScreenFix.PackageVerifier;

public sealed record PackageVerificationRequest(
    string Executable,
    string CanonicalIcon,
    BundleCompressionMode CompressionMode);

internal static class Program
{
    private const string ExecutableOption = "--executable";
    private const string CanonicalIconOption = "--canonical-icon";
    private const string CompressionOption = "--compression";

    private static readonly string[] RequiredOptions =
    [
        ExecutableOption,
        CanonicalIconOption,
        CompressionOption,
    ];

    internal static int Main(string[] args)
    {
        return Run(args, Console.Out, Console.Error);
    }

    internal static int Run(
        string[] args,
        TextWriter output,
        TextWriter error)
    {
        _ = output;
        if (!TryCreateRequest(args, out _, out var diagnostic))
        {
            error.WriteLine(diagnostic);
            return 2;
        }

        error.WriteLine("package verification is not implemented");
        return 1;
    }

    internal static bool TryCreateRequest(
        string[] args,
        out PackageVerificationRequest? request,
        out string diagnostic)
    {
        request = null;
        if (!TryReadOptions(args, out var values, out diagnostic))
        {
            return false;
        }

        if (!TryReadCompressionMode(
                values[CompressionOption],
                out var compressionMode,
                out diagnostic))
        {
            return false;
        }

        if (!TryValidateFile(
                values[ExecutableOption],
                ExecutableOption,
                out var executable,
                out diagnostic)
            || !TryValidateFile(
                values[CanonicalIconOption],
                CanonicalIconOption,
                out var canonicalIcon,
                out diagnostic))
        {
            return false;
        }

        request = new PackageVerificationRequest(
            executable,
            canonicalIcon,
            compressionMode);
        diagnostic = string.Empty;
        return true;
    }

    private static bool TryReadOptions(
        IReadOnlyList<string> args,
        out Dictionary<string, string> values,
        out string diagnostic)
    {
        values = new Dictionary<string, string>(StringComparer.Ordinal);
        for (var index = 0; index < args.Count; index++)
        {
            var option = args[index];
            if (!option.StartsWith("--", StringComparison.Ordinal))
            {
                diagnostic = $"unexpected argument: {option}";
                return false;
            }

            if (!RequiredOptions.Contains(option, StringComparer.Ordinal))
            {
                diagnostic = $"unknown option: {option}";
                return false;
            }

            if (values.ContainsKey(option))
            {
                diagnostic = $"option specified more than once: {option}";
                return false;
            }

            if (index + 1 >= args.Count
                || args[index + 1].StartsWith("--", StringComparison.Ordinal))
            {
                diagnostic = $"missing value for option: {option}";
                return false;
            }

            var value = args[++index];
            if (string.IsNullOrWhiteSpace(value))
            {
                diagnostic = $"value for option {option} must not be blank";
                return false;
            }

            values.Add(option, value);
        }

        foreach (var option in RequiredOptions)
        {
            if (!values.ContainsKey(option))
            {
                diagnostic = $"missing required option: {option}";
                return false;
            }
        }

        diagnostic = string.Empty;
        return true;
    }

    private static bool TryReadCompressionMode(
        string value,
        out BundleCompressionMode compressionMode,
        out string diagnostic)
    {
        switch (value)
        {
            case "compressed":
                compressionMode = BundleCompressionMode.Compressed;
                diagnostic = string.Empty;
                return true;
            case "uncompressed":
                compressionMode = BundleCompressionMode.Uncompressed;
                diagnostic = string.Empty;
                return true;
            default:
                compressionMode = default;
                diagnostic =
                    "invalid value for option --compression: expected compressed or uncompressed";
                return false;
        }
    }

    private static bool TryValidateFile(
        string path,
        string option,
        out string normalizedPath,
        out string diagnostic)
    {
        try
        {
            normalizedPath = Path.GetFullPath(path);
        }
        catch (Exception exception) when (
            exception is ArgumentException
                or NotSupportedException
                or PathTooLongException)
        {
            normalizedPath = string.Empty;
            diagnostic = $"invalid path for option {option}";
            return false;
        }

        if (!File.Exists(normalizedPath) && !Directory.Exists(normalizedPath))
        {
            diagnostic = $"file does not exist for option {option}: {normalizedPath}";
            return false;
        }

        try
        {
            var attributes = File.GetAttributes(normalizedPath);
            if ((attributes & FileAttributes.ReparsePoint) != 0)
            {
                diagnostic =
                    $"path is a symbolic link or reparse point for option {option}: " +
                    normalizedPath;
                return false;
            }

            if ((attributes & FileAttributes.Directory) != 0)
            {
                diagnostic = $"path is a directory for option {option}: {normalizedPath}";
                return false;
            }

            if (new FileInfo(normalizedPath).Length == 0)
            {
                diagnostic = $"file is empty for option {option}: {normalizedPath}";
                return false;
            }
        }
        catch (Exception exception) when (
            exception is IOException or UnauthorizedAccessException)
        {
            diagnostic = $"unable to inspect file for option {option}: {normalizedPath}";
            return false;
        }

        diagnostic = string.Empty;
        return true;
    }
}
