param(
    [Parameter(Mandatory = $true)]
    [string]$DotnetPath,
    [string]$PublishedExecutable,
    [ValidateSet("compressed", "uncompressed")]
    [string]$ExpectedCompression,
    [switch]$AllowDisposableAccountMutation
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

if ($AllowDisposableAccountMutation) {
    & $DotnetPath test $project -c Release --no-build `
        --filter "ScreenFixCategory=DisposableAccount"
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
