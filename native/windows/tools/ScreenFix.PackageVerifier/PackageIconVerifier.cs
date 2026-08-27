using ScreenFix.PackageVerifier.Bundle;
using ScreenFix.PackageVerifier.Resources;

namespace ScreenFix.PackageVerifier;

internal sealed record PackageVerificationResult(
    BundleCompressionMode CompressionMode,
    long ExecutableBytes,
    long ManagedAssemblyDeclaredBytes,
    long ManagedAssemblyStoredBytes,
    int IconBytes);

internal static class PackageIconVerifier
{
    internal static PackageVerificationResult Verify(
        PackageVerificationRequest request)
    {
        ArgumentNullException.ThrowIfNull(request);

        var assembly = SingleFileBundleReader.ExtractScreenFixAssembly(
            request.Executable,
            request.CompressionMode);
        var managedIcon = ManagedIconResourceReader.ReadScreenFixIcon(assembly.Bytes);
        var canonicalIcon = File.ReadAllBytes(request.CanonicalIcon);
        if (managedIcon.Length != canonicalIcon.Length)
        {
            throw new InvalidDataException(
                "managed icon length does not match canonical icon");
        }

        if (!managedIcon.AsSpan().SequenceEqual(canonicalIcon))
        {
            throw new InvalidDataException(
                "managed icon does not match canonical icon");
        }

        return new PackageVerificationResult(
            request.CompressionMode,
            new FileInfo(request.Executable).Length,
            assembly.DeclaredSize,
            assembly.StoredSize,
            managedIcon.Length);
    }
}
