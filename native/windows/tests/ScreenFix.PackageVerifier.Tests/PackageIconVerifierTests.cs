using ScreenFix.PackageVerifier.Bundle;

namespace ScreenFix.PackageVerifier.Tests;

public sealed class PackageIconVerifierTests : IDisposable
{
    private readonly string _temporaryDirectory;

    public PackageIconVerifierTests()
    {
        _temporaryDirectory = Path.Combine(
            Path.GetTempPath(),
            $"screenfix-package-verifier-tests-{Guid.NewGuid():N}");
        Directory.CreateDirectory(_temporaryDirectory);
    }

    [Theory]
    [InlineData("--executable")]
    [InlineData("--canonical-icon")]
    [InlineData("--compression")]
    public void Run_RejectsMissingRequiredOption(string omittedOption)
    {
        var arguments = CreateValidArguments();
        RemoveOption(arguments, omittedOption);

        AssertInvalid(arguments, $"missing required option: {omittedOption}");
    }

    [Theory]
    [InlineData("--executable")]
    [InlineData("--canonical-icon")]
    [InlineData("--compression")]
    public void Run_RejectsMissingOptionValue(string option)
    {
        var arguments = CreateValidArguments();
        arguments.RemoveAt(arguments.IndexOf(option) + 1);

        AssertInvalid(arguments, $"missing value for option: {option}");
    }

    [Theory]
    [InlineData("--executable")]
    [InlineData("--canonical-icon")]
    [InlineData("--compression")]
    public void Run_RejectsBlankOptionValue(string option)
    {
        var arguments = CreateValidArguments();
        arguments[arguments.IndexOf(option) + 1] = "   ";

        AssertInvalid(arguments, $"value for option {option} must not be blank");
    }

    [Theory]
    [InlineData("--executable")]
    [InlineData("--canonical-icon")]
    [InlineData("--compression")]
    public void Run_RejectsDuplicateOption(string option)
    {
        var arguments = CreateValidArguments();
        var value = arguments[arguments.IndexOf(option) + 1];
        arguments.Add(option);
        arguments.Add(value);

        AssertInvalid(arguments, $"option specified more than once: {option}");
    }

    [Fact]
    public void Run_RejectsUnknownOption()
    {
        var arguments = CreateValidArguments();
        arguments.Add("--unknown");
        arguments.Add("value");

        AssertInvalid(arguments, "unknown option: --unknown");
    }

    [Fact]
    public void Run_RejectsUnexpectedArgument()
    {
        var arguments = CreateValidArguments();
        arguments.Add("unexpected");

        AssertInvalid(arguments, "unexpected argument: unexpected");
    }

    [Fact]
    public void Run_RejectsInvalidCompressionMode()
    {
        var arguments = CreateValidArguments();
        ReplaceOptionValue(arguments, "--compression", "Compressed");

        AssertInvalid(
            arguments,
            "invalid value for option --compression: expected compressed or uncompressed");
    }

    [Theory]
    [InlineData("--executable")]
    [InlineData("--canonical-icon")]
    public void Run_RejectsNonexistentFile(string option)
    {
        var arguments = CreateValidArguments();
        var missingPath = Path.Combine(_temporaryDirectory, "missing-file");
        ReplaceOptionValue(arguments, option, missingPath);

        AssertInvalid(arguments, $"file does not exist for option {option}: {missingPath}");
    }

    [Theory]
    [InlineData("--executable")]
    [InlineData("--canonical-icon")]
    public void Run_RejectsDirectory(string option)
    {
        var arguments = CreateValidArguments();
        ReplaceOptionValue(arguments, option, _temporaryDirectory);

        AssertInvalid(
            arguments,
            $"path is a directory for option {option}: {_temporaryDirectory}");
    }

    [Theory]
    [InlineData("--executable")]
    [InlineData("--canonical-icon")]
    public void Run_RejectsEmptyFile(string option)
    {
        var arguments = CreateValidArguments();
        var emptyPath = Path.Combine(_temporaryDirectory, $"empty-{option[2..]}");
        File.Create(emptyPath).Dispose();
        ReplaceOptionValue(arguments, option, emptyPath);

        AssertInvalid(arguments, $"file is empty for option {option}: {emptyPath}");
    }

    [Theory]
    [InlineData("--executable")]
    [InlineData("--canonical-icon")]
    public void Run_RejectsSymbolicLink(string option)
    {
        var arguments = CreateValidArguments();
        var targetPath = CreateFile($"symlink-target-{option[2..]}");
        var linkPath = Path.Combine(_temporaryDirectory, $"symlink-{option[2..]}");
        File.CreateSymbolicLink(linkPath, targetPath);
        ReplaceOptionValue(arguments, option, linkPath);

        AssertInvalid(
            arguments,
            $"path is a symbolic link or reparse point for option {option}: {linkPath}");
    }

    [Theory]
    [InlineData("compressed", BundleCompressionMode.Compressed)]
    [InlineData("uncompressed", BundleCompressionMode.Uncompressed)]
    public void ValidArguments_VerifyPackageAndReturnSuccess(
        string modeArgument,
        BundleCompressionMode expectedMode)
    {
        var arguments = CreateValidArguments(modeArgument);
        var executable = Path.GetFullPath(arguments[1]);
        var canonicalIcon = Path.GetFullPath(arguments[3]);

        var parsed = Program.TryCreateRequest(
            [.. arguments],
            out var request,
            out var diagnostic);

        Assert.True(parsed);
        Assert.Equal(
            new PackageVerificationRequest(executable, canonicalIcon, expectedMode),
            request);
        Assert.Empty(diagnostic);

        var result = Invoke(arguments);

        var executableBytes = new FileInfo(executable).Length;
        var assemblyBytes = new ManagedPeFixtureBuilder().Build().LongLength;
        var storedBytes = ReadStoredAssemblyBytes(executable, expectedMode);
        Assert.Equal(0, result.ExitCode);
        Assert.Equal(
            $"verified mode={modeArgument} executable-bytes={executableBytes} "
                + $"managed-declared-bytes={assemblyBytes} "
                + $"managed-stored-bytes={storedBytes} "
                + $"icon-bytes={ManagedPeFixtureBuilder.IconBytes.Length}"
                + Environment.NewLine,
            result.Output);
        Assert.Empty(result.Error);
    }

    [Fact]
    public void Verify_RejectsManagedIconWithWrongLength()
    {
        var shorterIcon = ManagedPeFixtureBuilder.IconBytes[..^1];
        var builder = new ManagedPeFixtureBuilder
        {
            ManagedResourceDirectoryBytes = CreateResourceBlob(shorterIcon),
        };
        var executable = CreateBundle(
            "uncompressed",
            builder.Build());
        var canonicalIcon = CreateFile(
            "canonical-wrong-length.ico",
            ManagedPeFixtureBuilder.IconBytes);

        var exception = Assert.Throws<InvalidDataException>(() =>
            PackageIconVerifier.Verify(new PackageVerificationRequest(
                executable,
                canonicalIcon,
                BundleCompressionMode.Uncompressed)));

        Assert.Contains(
            "managed icon length does not match canonical icon",
            exception.Message,
            StringComparison.Ordinal);
    }

    [Fact]
    public void Verify_RejectsOneByteMutatedManagedIcon()
    {
        var mutatedIcon = (byte[])ManagedPeFixtureBuilder.IconBytes.Clone();
        mutatedIcon[^1] ^= 0xff;
        var builder = new ManagedPeFixtureBuilder
        {
            ManagedResourceDirectoryBytes = CreateResourceBlob(mutatedIcon),
        };
        var executable = CreateBundle(
            "uncompressed",
            builder.Build());
        var canonicalIcon = CreateFile(
            "canonical-mutated.ico",
            ManagedPeFixtureBuilder.IconBytes);

        var exception = Assert.Throws<InvalidDataException>(() =>
            PackageIconVerifier.Verify(new PackageVerificationRequest(
                executable,
                canonicalIcon,
                BundleCompressionMode.Uncompressed)));

        Assert.Contains(
            "managed icon does not match canonical icon",
            exception.Message,
            StringComparison.Ordinal);
    }

    [Fact]
    public void Run_VerificationFailureReturnsExitOneWithoutSuccessOutput()
    {
        var arguments = CreateValidArguments("uncompressed");
        File.WriteAllBytes(arguments[3], [0x01]);

        var result = Invoke(arguments);

        Assert.Equal(1, result.ExitCode);
        Assert.Empty(result.Output);
        Assert.Equal(
            $"managed icon length does not match canonical icon{Environment.NewLine}",
            result.Error);
    }

    [Fact]
    public void Run_ZeroMetadataDirectoryReturnsControlledInvalidPeFailure()
    {
        var assembly = new ManagedPeFixtureBuilder().Build();
        ManagedPeFixtureBuilder.RemoveMetadataDirectory(assembly);
        var arguments = new List<string>
        {
            "--executable",
            CreateBundle("uncompressed", assembly),
            "--canonical-icon",
            CreateFile("metadata-missing.ico", ManagedPeFixtureBuilder.IconBytes),
            "--compression",
            "uncompressed",
        };

        var result = Invoke(arguments);

        Assert.Equal(1, result.ExitCode);
        Assert.Empty(result.Output);
        Assert.Equal(
            $"managed assembly is not a valid PE image{Environment.NewLine}",
            result.Error);
        Assert.DoesNotContain("System.", result.Error, StringComparison.Ordinal);
        Assert.DoesNotContain(" at ", result.Error, StringComparison.Ordinal);
    }

    public void Dispose()
    {
        Directory.Delete(_temporaryDirectory, recursive: true);
    }

    private void AssertInvalid(IReadOnlyList<string> arguments, string diagnostic)
    {
        var result = Invoke(arguments);

        Assert.Equal(2, result.ExitCode);
        Assert.Empty(result.Output);
        Assert.Equal($"{diagnostic}{Environment.NewLine}", result.Error);
    }

    private List<string> CreateValidArguments(string compressionMode = "compressed")
    {
        return
        [
            "--executable",
            CreateBundle(compressionMode),
            "--canonical-icon",
            CreateFile("ScreenFix.ico", ManagedPeFixtureBuilder.IconBytes),
            "--compression",
            compressionMode,
        ];
    }

    private string CreateFile(string fileName, byte[]? bytes = null)
    {
        var path = Path.Combine(_temporaryDirectory, fileName);
        File.WriteAllBytes(path, bytes ?? [1]);
        return path;
    }

    private string CreateBundle(string compressionMode, byte[]? assemblyBytes = null)
    {
        assemblyBytes ??= new ManagedPeFixtureBuilder().Build();
        var builder = new BundleFixtureBuilder();
        builder.Entries[0].Payload = assemblyBytes;
        builder.Entries[0].Size = assemblyBytes.LongLength;
        if (compressionMode == "compressed")
        {
            var compressed = BundleFixtureBuilder.CreateStoredDeflate(
                assemblyBytes);
            builder.Entries[0].Payload = compressed;
            builder.Entries[0].CompressedSize = compressed.LongLength;
        }

        var path = Path.Combine(_temporaryDirectory, "ScreenFix.exe");
        File.WriteAllBytes(path, builder.Build());
        return path;
    }

    private static long ReadStoredAssemblyBytes(
        string executable,
        BundleCompressionMode mode)
    {
        return SingleFileBundleReader.ExtractScreenFixAssembly(executable, mode)
            .StoredSize;
    }

    private static byte[] CreateResourceBlob(byte[] payload)
    {
        var blob = new byte[sizeof(int) + payload.Length];
        System.Buffers.Binary.BinaryPrimitives.WriteInt32LittleEndian(
            blob,
            payload.Length);
        payload.CopyTo(blob.AsSpan(sizeof(int)));
        return blob;
    }

    private static InvocationResult Invoke(IReadOnlyList<string> arguments)
    {
        using var output = new StringWriter();
        using var error = new StringWriter();
        var exitCode = Program.Run([.. arguments], output, error);
        return new InvocationResult(exitCode, output.ToString(), error.ToString());
    }

    private static void RemoveOption(List<string> arguments, string option)
    {
        var index = arguments.IndexOf(option);
        arguments.RemoveRange(index, 2);
    }

    private static void ReplaceOptionValue(
        List<string> arguments,
        string option,
        string value)
    {
        arguments[arguments.IndexOf(option) + 1] = value;
    }

    private sealed record InvocationResult(int ExitCode, string Output, string Error);
}
