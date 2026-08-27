param(
    [Parameter(Mandatory = $true)]
    [string]$DotnetPath,
    [string]$PublishedExecutable,
    [ValidateSet("compressed", "uncompressed")]
    [string]$ExpectedCompression,
    [switch]$AllowDisposableAccountMutation,
    [switch]$MeasureStartup,
    [string]$CompressedExecutable,
    [string]$UncompressedExecutable
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($DotnetPath) `
    -or -not [IO.Path]::IsPathFullyQualified($DotnetPath)) {
    throw "dotnet path must be one absolute regular non-reparse executable file"
}

$DotnetPath = [IO.Path]::GetFullPath($DotnetPath)
if (-not (Test-Path -LiteralPath $DotnetPath -PathType Leaf)) {
    throw "dotnet path must be one absolute regular non-reparse executable file"
}

$dotnetFile = Get-Item -LiteralPath $DotnetPath
if ($dotnetFile.Length -eq 0 `
    -or ($dotnetFile.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    throw "dotnet path must be one absolute regular non-reparse executable file"
}

if ($IsWindows) {
    if (@(".exe", ".com", ".cmd", ".bat", ".ps1") -cnotcontains `
        $dotnetFile.Extension.ToLowerInvariant()) {
        throw "dotnet path must be one absolute regular non-reparse executable file"
    }
}
else {
    $executeMask = [int]([IO.UnixFileMode]::UserExecute -bor `
        [IO.UnixFileMode]::GroupExecute -bor `
        [IO.UnixFileMode]::OtherExecute)
    $mode = [int][IO.File]::GetUnixFileMode($DotnetPath)
    if (($mode -band $executeMask) -eq 0) {
        throw "dotnet path must be one absolute regular non-reparse executable file"
    }
}

if ($AllowDisposableAccountMutation) {
    $runnerTempIsAbsolute = -not [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP) `
        -and [IO.Path]::IsPathFullyQualified($env:RUNNER_TEMP)
    if ($env:CI -cne "true" `
        -or $env:GITHUB_ACTIONS -cne "true" `
        -or $env:SCREENFIX_RUNNER_ENVIRONMENT -cne "github-hosted" `
        -or -not $runnerTempIsAbsolute) {
        throw "disposable account mutation requires CI=true, GITHUB_ACTIONS=true, SCREENFIX_RUNNER_ENVIRONMENT=github-hosted, and an absolute RUNNER_TEMP"
    }
}

function Resolve-StartupExecutable {
    param(
        [string]$Path,
        [string]$ExpectedName
    )

    if ([string]::IsNullOrWhiteSpace($Path) `
        -or -not [IO.Path]::IsPathFullyQualified($Path)) {
        throw "startup measurement requires an absolute $ExpectedName path"
    }

    $resolved = [IO.Path]::GetFullPath($Path)
    $file = Get-Item -LiteralPath $resolved -Force -ErrorAction SilentlyContinue
    if ($null -eq $file `
        -or $file -isnot [IO.FileInfo] `
        -or $file.Name -cne $ExpectedName `
        -or $file.Length -le 0 `
        -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "startup measurement requires one regular nonempty non-reparse $ExpectedName"
    }

    return $resolved
}

$project = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "../tests/ScreenFix.Windows.Tests/ScreenFix.Windows.Tests.csproj"))
$verifierProject = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "../tools/ScreenFix.PackageVerifier/ScreenFix.PackageVerifier.csproj"))
$canonicalIcon = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "../src/ScreenFix.App/Resources/ScreenFix.ico"))
$hasPublishedExecutable = -not [string]::IsNullOrWhiteSpace($PublishedExecutable)
if ($hasPublishedExecutable) {
    if ([string]::IsNullOrWhiteSpace($ExpectedCompression)) {
        throw "expected compression is required with a published executable"
    }

    $PublishedExecutable = [IO.Path]::GetFullPath($PublishedExecutable)
    $publishedFile = Get-Item `
        -LiteralPath $PublishedExecutable `
        -Force `
        -ErrorAction SilentlyContinue
    if ($null -eq $publishedFile `
        -or $publishedFile -isnot [IO.FileInfo] `
        -or $publishedFile.Length -le 0 `
        -or ($publishedFile.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "published executable does not exist"
    }
}
elseif (-not [string]::IsNullOrWhiteSpace($ExpectedCompression)) {
    throw "published executable is required with expected compression"
}

$hasCompressedStartupExecutable = -not [string]::IsNullOrWhiteSpace(
    $CompressedExecutable)
$hasUncompressedStartupExecutable = -not [string]::IsNullOrWhiteSpace(
    $UncompressedExecutable)
if ($MeasureStartup) {
    if (-not $AllowDisposableAccountMutation) {
        throw "startup measurement requires -AllowDisposableAccountMutation"
    }
    if ($hasPublishedExecutable `
        -or -not [string]::IsNullOrWhiteSpace($ExpectedCompression)) {
        throw "startup measurement cannot be combined with one-package verification"
    }

    $CompressedExecutable = Resolve-StartupExecutable `
        -Path $CompressedExecutable `
        -ExpectedName "ScreenFix-Windows-x64.exe"
    $UncompressedExecutable = Resolve-StartupExecutable `
        -Path $UncompressedExecutable `
        -ExpectedName "ScreenFix-Windows-x64-uncompressed.exe"
}
elseif ($hasCompressedStartupExecutable -or $hasUncompressedStartupExecutable) {
    throw "startup executable paths require -MeasureStartup"
}

& $DotnetPath build $project -c Release
if ($LASTEXITCODE -ne 0) {
    throw "Windows native test build failed with exit code $LASTEXITCODE"
}

if ($hasPublishedExecutable) {
    & $DotnetPath run --project $verifierProject -c Release -- `
        --executable $PublishedExecutable `
        --canonical-icon $canonicalIcon `
        --compression $ExpectedCompression
    if ($LASTEXITCODE -ne 0) {
        throw "published executable managed icon verification failed with exit code $LASTEXITCODE"
    }
}

if (-not $IsWindows) {
    Write-Output "Windows native tests compiled; execution requires Windows."
    return
}

if ($MeasureStartup) {
    $previousAllow = $env:SCREENFIX_ALLOW_DISPOSABLE_ACCOUNT_MUTATION
    $previousCompressed = $env:SCREENFIX_STARTUP_COMPRESSED_EXE
    $previousUncompressed = $env:SCREENFIX_STARTUP_UNCOMPRESSED_EXE
    try {
        $env:SCREENFIX_ALLOW_DISPOSABLE_ACCOUNT_MUTATION = "true"
        $env:SCREENFIX_STARTUP_COMPRESSED_EXE = $CompressedExecutable
        $env:SCREENFIX_STARTUP_UNCOMPRESSED_EXE = $UncompressedExecutable
        & $DotnetPath test $project -c Release --no-build `
            --filter "(ScreenFixCategory=DisposableAccount)&(ScreenFixStartup=Measurement)" `
            --logger "console;verbosity=detailed"
        if ($LASTEXITCODE -ne 0) {
            throw "Windows startup measurement failed with exit code $LASTEXITCODE"
        }
    }
    finally {
        $env:SCREENFIX_ALLOW_DISPOSABLE_ACCOUNT_MUTATION = $previousAllow
        $env:SCREENFIX_STARTUP_COMPRESSED_EXE = $previousCompressed
        $env:SCREENFIX_STARTUP_UNCOMPRESSED_EXE = $previousUncompressed
    }

    return
}

if ($AllowDisposableAccountMutation) {
    & $DotnetPath test $project -c Release --no-build `
        --filter "(ScreenFixCategory=DisposableAccount)&(ScreenFixStartup!=Measurement)"
    if ($LASTEXITCODE -ne 0) {
        throw "disposable-account Windows tests failed with exit code $LASTEXITCODE"
    }

    return
}

& $DotnetPath test $project -c Release --no-build `
    --filter "(FullyQualifiedName!~PublishedExecutableIconTests)&(ScreenFixCategory!=DisposableAccount)"
if ($LASTEXITCODE -ne 0) {
    throw "Windows native tests failed with exit code $LASTEXITCODE"
}

if (-not $hasPublishedExecutable) {
    return
}

$previousExecutable = $env:SCREENFIX_PUBLISHED_EXE
$previousCanonical = $env:SCREENFIX_CANONICAL_ICO
try {
    $env:SCREENFIX_PUBLISHED_EXE = $PublishedExecutable
    $env:SCREENFIX_CANONICAL_ICO = $canonicalIcon
    & $DotnetPath test $project -c Release --no-build `
        --filter "FullyQualifiedName~PublishedExecutableIconTests"
    if ($LASTEXITCODE -ne 0) {
        throw "published executable icon tests failed with exit code $LASTEXITCODE"
    }
}
finally {
    $env:SCREENFIX_PUBLISHED_EXE = $previousExecutable
    $env:SCREENFIX_CANONICAL_ICO = $previousCanonical
}
