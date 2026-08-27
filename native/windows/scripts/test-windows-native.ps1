param(
    [string]$DotnetPath,
    [string]$PublishedExecutable,
    [ValidateSet("compressed", "uncompressed")]
    [string]$ExpectedCompression
)

$ErrorActionPreference = "Stop"

if (-not $PSBoundParameters.ContainsKey("DotnetPath")) {
    $DotnetPath = (Get-Command dotnet -ErrorAction Stop).Source
}

if ([string]::IsNullOrWhiteSpace($DotnetPath) `
    -or -not [IO.Path]::IsPathFullyQualified($DotnetPath)) {
    throw "dotnet path must be one absolute regular nonempty file"
}

$DotnetPath = [IO.Path]::GetFullPath($DotnetPath)
if (-not (Test-Path -LiteralPath $DotnetPath -PathType Leaf)) {
    throw "dotnet path must be one absolute regular nonempty file"
}

$dotnetFile = Get-Item -LiteralPath $DotnetPath
if ($dotnetFile.Length -eq 0 `
    -or ($dotnetFile.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    throw "dotnet path must be one absolute regular nonempty file"
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
    if (-not (Test-Path -LiteralPath $PublishedExecutable -PathType Leaf)) {
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

& $DotnetPath test $project -c Release --no-build `
    --filter "FullyQualifiedName!~PublishedExecutableIconTests"
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
