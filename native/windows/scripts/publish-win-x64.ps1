param(
    [Parameter(Mandatory = $true)]
    [string]$DotnetPath,
    [Parameter(Mandatory = $true)]
    [string]$ExternalDotnetPath,
    [switch]$MeasureStartup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "../../.."))
$project = [IO.Path]::GetFullPath(
    (Join-Path $repositoryRoot "native/windows/src/ScreenFix.App/ScreenFix.App.csproj"))
$toolchainPreflight = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "assert-pinned-win-x64-toolchain-preflight.ps1"))
& $toolchainPreflight `
    -DotnetPath $DotnetPath `
    -ExternalDotnetPath $ExternalDotnetPath `
    -Project $project |
    ForEach-Object { Write-Host $_ }
$DotnetPath = [IO.Path]::GetFullPath($DotnetPath)
$ExternalDotnetPath = [IO.Path]::GetFullPath($ExternalDotnetPath)

function Test-PathBeneath {
    param(
        [string]$Parent,
        [string]$Child
    )

    $relative = [IO.Path]::GetRelativePath($Parent, $Child)
    if ($relative -ceq "." -or [IO.Path]::IsPathFullyQualified($relative)) {
        return $false
    }

    return $relative -cne ".." `
        -and -not $relative.StartsWith(
            ".." + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::Ordinal) `
        -and -not $relative.StartsWith(
            ".." + [IO.Path]::AltDirectorySeparatorChar,
            [StringComparison]::Ordinal)
}

function Assert-NoReparseAncestor {
    param(
        [string]$Path,
        [string]$Boundary
    )

    $current = [IO.Path]::GetFullPath($Path)
    while ($true) {
        $item = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
        if ($null -ne $item `
            -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "generated output path must not have a reparse-point ancestor: $Path"
        }
        if ($current -ceq $Boundary) {
            return
        }

        $parent = [IO.Path]::GetDirectoryName($current)
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -ceq $current) {
            throw "generated output path must remain beneath the repository: $Path"
        }
        $current = $parent
    }
}

function Resolve-GeneratedRoot {
    param([string]$RelativePath)

    $resolved = [IO.Path]::GetFullPath((Join-Path $windowsArtifactsRoot $RelativePath))
    if (-not (Test-PathBeneath -Parent $windowsArtifactsRoot -Child $resolved)) {
        throw "generated output path must remain beneath the Windows artifacts root: $resolved"
    }

    Assert-NoReparseAncestor -Path $resolved -Boundary $repositoryRoot
    return $resolved
}

function Remove-GeneratedRoot {
    param([string]$Path)

    Assert-NoReparseAncestor -Path $Path -Boundary $repositoryRoot
    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
}

function Invoke-Publish {
    param(
        [ValidateSet("compressed", "uncompressed")]
        [string]$Mode,
        [string]$ArtifactsPath,
        [string]$OutputPath
    )

    $compression = if ($Mode -ceq "compressed") { "true" } else { "false" }
    $arguments = @(
        "publish",
        $project,
        "-c", "Release",
        "-r", "win-x64",
        "--self-contained", "true",
        "--artifacts-path", $ArtifactsPath,
        "-o", $OutputPath,
        "-p:PublishSingleFile=true",
        "-p:IncludeNativeLibrariesForSelfExtract=true",
        "-p:EnableCompressionInSingleFile=$compression",
        "-p:PublishTrimmed=false",
        "-p:DebugType=None",
        "-p:DebugSymbols=false",
        "-p:UseAppHost=true")

    $output = @(& $DotnetPath @arguments 2>&1)
    $exitCode = $LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }
    if ($exitCode -ne 0) {
        throw "$Mode dotnet publish failed with exit code $exitCode"
    }
}

function Resolve-AppAssetsPath {
    param(
        [string]$ArtifactsPath,
        [ValidateSet("compressed", "uncompressed")]
        [string]$Mode
    )

    $matches = @(Get-ChildItem `
        -LiteralPath $ArtifactsPath `
        -Recurse `
        -File `
        -Filter "project.assets.json" | Where-Object {
            $relative = [IO.Path]::GetRelativePath($ArtifactsPath, $_.FullName)
            $relative -match '^obj[\\/]ScreenFix\.App[\\/]project\.assets\.json$'
        })
    if ($matches.Count -ne 1) {
        throw "$Mode artifacts must contain exactly one ScreenFix.App project.assets.json; found $($matches.Count)"
    }

    return [IO.Path]::GetFullPath($matches[0].FullName)
}

function Resolve-PublishedExecutable {
    param(
        [string]$OutputPath,
        [ValidateSet("compressed", "uncompressed")]
        [string]$Mode
    )

    $entries = @(Get-ChildItem -LiteralPath $OutputPath -Force)
    if ($entries.Count -ne 1 `
        -or $entries[0] -isnot [IO.FileInfo] `
        -or $entries[0].Name -cne "ScreenFix.exe" `
        -or $entries[0].Length -le 0 `
        -or ($entries[0].Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "$Mode publish output must contain exactly one regular nonempty ScreenFix.exe"
    }

    return [IO.Path]::GetFullPath($entries[0].FullName)
}

function Invoke-ModeVerification {
    param(
        [string]$Executable,
        [string]$OutputPath,
        [ValidateSet("compressed", "uncompressed")]
        [string]$Mode
    )

    & $packageAssertion -OutputDirectory $OutputPath |
        ForEach-Object { Write-Host $_ }
    & $windowsNativeTests `
        -DotnetPath $DotnetPath `
        -PublishedExecutable $Executable `
        -ExpectedCompression $Mode |
        ForEach-Object { Write-Host $_ }
}

function Assert-SizeGate {
    param(
        [string]$CompressedExecutable,
        [string]$UncompressedExecutable
    )

    $compressedLength = (Get-Item -LiteralPath $CompressedExecutable).Length
    $uncompressedLength = (Get-Item -LiteralPath $UncompressedExecutable).Length
    if ($compressedLength -ge $uncompressedLength) {
        throw "compressed executable must be smaller than uncompressed executable"
    }

    $maximumCompressedBytes = [long][Math]::Floor(
        [decimal]$uncompressedLength * [decimal]0.80)
    if ($compressedLength -gt $maximumCompressedBytes) {
        throw (
            "compressed executable exceeds 80 percent of uncompressed executable: " +
            "$compressedLength > $maximumCompressedBytes")
    }
}

function Clear-PublishIntermediates {
    $paths = @($buildRoots.Values) + @($objectRoots.Values)
    foreach ($path in $paths) {
        Remove-GeneratedRoot -Path $path
    }
}

function Invoke-PublishRound {
    Clear-PublishIntermediates

    $executables = @{}
    $assets = @{}
    foreach ($mode in @("uncompressed", "compressed")) {
        Invoke-Publish `
            -Mode $mode `
            -ArtifactsPath $objectRoots[$mode] `
            -OutputPath $buildRoots[$mode]
        $executables[$mode] = Resolve-PublishedExecutable `
            -OutputPath $buildRoots[$mode] `
            -Mode $mode
        $assets[$mode] = Resolve-AppAssetsPath `
            -ArtifactsPath $objectRoots[$mode] `
            -Mode $mode
    }

    & $toolchainAssertion `
        -DotnetPath $DotnetPath `
        -ExternalDotnetPath $ExternalDotnetPath `
        -Project $project `
        -BaselineAssetsPath $assets["uncompressed"] `
        -CandidateAssetsPath $assets["compressed"] |
        ForEach-Object { Write-Host $_ }

    foreach ($mode in @("uncompressed", "compressed")) {
        Invoke-ModeVerification `
            -Executable $executables[$mode] `
            -OutputPath $buildRoots[$mode] `
            -Mode $mode
    }
    Assert-SizeGate `
        -CompressedExecutable $executables["compressed"] `
        -UncompressedExecutable $executables["uncompressed"]

    return [pscustomobject]@{
        Compressed = $executables["compressed"]
        Uncompressed = $executables["uncompressed"]
    }
}

function Test-FileBytesEqual {
    param(
        [string]$First,
        [string]$Second
    )

    $firstStream = [IO.File]::OpenRead($First)
    try {
        $secondStream = [IO.File]::OpenRead($Second)
        try {
            if ($firstStream.Length -ne $secondStream.Length) {
                return $false
            }

            $firstBuffer = [byte[]]::new(1024 * 1024)
            $secondBuffer = [byte[]]::new($firstBuffer.Length)
            while ($true) {
                $firstRead = $firstStream.Read($firstBuffer, 0, $firstBuffer.Length)
                $secondRead = $secondStream.Read($secondBuffer, 0, $secondBuffer.Length)
                if ($firstRead -ne $secondRead) {
                    return $false
                }
                if ($firstRead -eq 0) {
                    return $true
                }
                if (-not [Collections.StructuralComparisons]::StructuralEqualityComparer.Equals(
                        $firstBuffer,
                        $secondBuffer)) {
                    return $false
                }
            }
        }
        finally {
            $secondStream.Dispose()
        }
    }
    finally {
        $firstStream.Dispose()
    }
}

function Assert-SourceMatchesStaged {
    param(
        [string]$Source,
        [string]$Staged,
        [string]$Name
    )

    $sourceHash = (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash
    $stagedHash = (Get-FileHash -LiteralPath $Staged -Algorithm SHA256).Hash
    if ($sourceHash -cne $stagedHash `
        -or -not (Test-FileBytesEqual -First $Source -Second $Staged)) {
        throw "$Name staged bytes differ from the verified publish output"
    }

    Write-Output "$Name deterministic sha256=$sourceHash"
}

$windowsArtifactsRoot = [IO.Path]::GetFullPath(
    (Join-Path $repositoryRoot "native/windows/artifacts/windows"))
$packageAssertion = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "assert-win-x64-package.ps1"))
$executableAssertion = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "assert-win-x64-executable.ps1"))
$releaseAssertion = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "assert-win-x64-release.ps1"))
$toolchainAssertion = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "assert-pinned-win-x64-toolchain.ps1"))
$windowsNativeTests = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "test-windows-native.ps1"))
$transactionModule = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "WindowsReleaseTransaction.psm1"))

$buildRoots = @{
    uncompressed = Resolve-GeneratedRoot -RelativePath "build/uncompressed"
    compressed = Resolve-GeneratedRoot -RelativePath "build/compressed"
}
$objectRoots = @{
    uncompressed = Resolve-GeneratedRoot -RelativePath "obj/uncompressed"
    compressed = Resolve-GeneratedRoot -RelativePath "obj/compressed"
}
$releaseRoot = Resolve-GeneratedRoot -RelativePath "release"
$recommendedName = "ScreenFix-Windows-x64.exe"
$fallbackName = "ScreenFix-Windows-x64-uncompressed.exe"

$firstRound = Invoke-PublishRound
Import-Module $transactionModule -Force
try {
    $verifyCandidate = {
        param([string]$candidate)

        foreach ($staged in @(
                [pscustomobject]@{
                    Path = (Join-Path $candidate $recommendedName)
                    Name = $recommendedName
                    Mode = "compressed"
                    Source = $firstRound.Compressed
                },
                [pscustomobject]@{
                    Path = (Join-Path $candidate $fallbackName)
                    Name = $fallbackName
                    Mode = "uncompressed"
                    Source = $firstRound.Uncompressed
                })) {
            & $executableAssertion `
                -Executable $staged.Path `
                -ExpectedFileName $staged.Name |
                ForEach-Object { Write-Host $_ }
            & $windowsNativeTests `
                -DotnetPath $DotnetPath `
                -PublishedExecutable $staged.Path `
                -ExpectedCompression $staged.Mode |
                ForEach-Object { Write-Host $_ }
            Assert-SourceMatchesStaged `
                -Source $staged.Source `
                -Staged $staged.Path `
                -Name $staged.Name |
                ForEach-Object { Write-Host $_ }
        }

        & $releaseAssertion -ReleaseDirectory $candidate |
            ForEach-Object { Write-Host $_ }
    }
    $buildSecondRound = {
        Invoke-PublishRound
    }

    $finalRelease = Invoke-WindowsReleaseTransaction `
        -ArtifactsParent $windowsArtifactsRoot `
        -ReleaseDirectory $releaseRoot `
        -CompressedSource $firstRound.Compressed `
        -UncompressedSource $firstRound.Uncompressed `
        -VerifyCandidate $verifyCandidate `
        -BuildSecondRound $buildSecondRound
    & $releaseAssertion -ReleaseDirectory $finalRelease
}
finally {
    Remove-Module WindowsReleaseTransaction -ErrorAction SilentlyContinue
}

if ($MeasureStartup) {
    & $windowsNativeTests `
        -DotnetPath $DotnetPath `
        -AllowDisposableAccountMutation `
        -MeasureStartup `
        -CompressedExecutable (Join-Path $finalRelease $recommendedName) `
        -UncompressedExecutable (Join-Path $finalRelease $fallbackName) |
        ForEach-Object { Write-Host $_ }
}
