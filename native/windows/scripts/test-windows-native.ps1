param(
    [string]$PublishedExecutable
)

$ErrorActionPreference = "Stop"

$project = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "../tests/ScreenFix.Windows.Tests/ScreenFix.Windows.Tests.csproj"))
$canonicalIcon = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "../src/ScreenFix.App/Resources/ScreenFix.ico"))
$hasPublishedExecutable = -not [string]::IsNullOrWhiteSpace($PublishedExecutable)
if ($hasPublishedExecutable) {
    $PublishedExecutable = [IO.Path]::GetFullPath($PublishedExecutable)
    if (-not (Test-Path -LiteralPath $PublishedExecutable -PathType Leaf)) {
        throw "published executable does not exist"
    }
}

& dotnet build $project -c Release
if ($LASTEXITCODE -ne 0) {
    throw "Windows native test build failed with exit code $LASTEXITCODE"
}

if (-not $IsWindows) {
    if ($hasPublishedExecutable) {
        throw "published executable icon tests require Windows"
    }

    Write-Output "Windows native tests compiled; execution requires Windows."
    return
}

& dotnet test $project -c Release --no-build `
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
    & dotnet test $project -c Release --no-build `
        --filter "FullyQualifiedName~PublishedExecutableIconTests"
    if ($LASTEXITCODE -ne 0) {
        throw "published executable icon tests failed with exit code $LASTEXITCODE"
    }
}
finally {
    $env:SCREENFIX_PUBLISHED_EXE = $previousExecutable
    $env:SCREENFIX_CANONICAL_ICO = $previousCanonical
}
