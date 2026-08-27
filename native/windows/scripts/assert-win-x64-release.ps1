param(
    [Parameter(Mandatory = $true)]
    [string]$ReleaseDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$recommendedName = "ScreenFix-Windows-x64.exe"
$fallbackName = "ScreenFix-Windows-x64-uncompressed.exe"
$approvedNames = @($recommendedName, $fallbackName)
$executableAssertion = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "assert-win-x64-executable.ps1"))

if ([string]::IsNullOrWhiteSpace($ReleaseDirectory) `
    -or -not [IO.Path]::IsPathFullyQualified($ReleaseDirectory)) {
    throw "release directory must be absolute"
}

$ReleaseDirectory = [IO.Path]::GetFullPath($ReleaseDirectory)
$releaseItem = Get-Item `
    -LiteralPath $ReleaseDirectory `
    -Force `
    -ErrorAction SilentlyContinue
if ($null -eq $releaseItem `
    -or $releaseItem -isnot [IO.DirectoryInfo] `
    -or ($releaseItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    throw "release directory must be one regular non-reparse directory"
}

$entries = @(Get-ChildItem -LiteralPath $ReleaseDirectory -Force)
foreach ($approvedName in $approvedNames) {
    if ($entries.Name -cnotcontains $approvedName) {
        throw "release directory is missing $approvedName"
    }
}

$unexpected = @($entries | Where-Object {
    $approvedNames -cnotcontains $_.Name
} | Sort-Object -Property Name -CaseSensitive)
if ($unexpected.Count -gt 0) {
    throw "release directory contains unexpected entry: $($unexpected[0].Name)"
}

$assets = @{}
foreach ($approvedName in $approvedNames) {
    $asset = @($entries | Where-Object { $_.Name -ceq $approvedName })
    if ($asset.Count -ne 1 `
        -or $asset[0] -isnot [IO.FileInfo] `
        -or $asset[0].Length -le 0 `
        -or ($asset[0].Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "release asset must be one regular non-reparse nonempty file: $approvedName"
    }

    $assets[$approvedName] = $asset[0]
    $null = & $executableAssertion `
        -Executable $asset[0].FullName `
        -ExpectedFileName $approvedName
}

$recommended = $assets[$recommendedName]
$fallback = $assets[$fallbackName]
if ($recommended.Length -ge $fallback.Length) {
    throw "compressed release asset must be smaller than uncompressed release asset"
}

$maximumRecommendedBytes = [long][Math]::Floor(
    [decimal]$fallback.Length * [decimal]0.80)
if ($recommended.Length -gt $maximumRecommendedBytes) {
    throw (
        "compressed release asset exceeds 80 percent of uncompressed release asset: " +
        "$($recommended.Length) > $maximumRecommendedBytes")
}

$recommendedHash = (Get-FileHash `
    -LiteralPath $recommended.FullName `
    -Algorithm SHA256).Hash
$fallbackHash = (Get-FileHash `
    -LiteralPath $fallback.FullName `
    -Algorithm SHA256).Hash
$reduction = (
    [decimal]($fallback.Length - $recommended.Length) * [decimal]100 `
        / [decimal]$fallback.Length)
$reductionText = $reduction.ToString(
    "F2",
    [Globalization.CultureInfo]::InvariantCulture)

Write-Output "$recommendedName size=$($recommended.Length) sha256=$recommendedHash"
Write-Output "$fallbackName size=$($fallback.Length) sha256=$fallbackHash"
Write-Output "compressed reduction=$reductionText percent"
