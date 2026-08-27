param(
    [Parameter(Mandatory = $true)]
    [string]$ReadmePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ReadmePath) `
    -or -not [IO.Path]::IsPathFullyQualified($ReadmePath)) {
    throw "README path must be absolute"
}

$ReadmePath = [IO.Path]::GetFullPath($ReadmePath)
$readme = Get-Item -LiteralPath $ReadmePath -Force -ErrorAction SilentlyContinue
if ($null -eq $readme `
    -or $readme -isnot [IO.FileInfo] `
    -or $readme.Length -le 0 `
    -or ($readme.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    throw "README path must be one regular nonempty non-reparse file"
}

$content = [IO.File]::ReadAllText($ReadmePath)
$normalizedContent = [Text.RegularExpressions.Regex]::Replace(
    $content,
    '\s+',
    ' ')
$recommendedMarker = (
    '`ScreenFix-Windows-x64.exe` is the recommended smaller self-contained download.')
$fallbackMarker = (
    '`ScreenFix-Windows-x64-uncompressed.exe` is the behavior-identical ' +
    'uncompressed fallback for startup or extraction trouble.')
$runtimeMarker = (
    'Neither download needs a separate .NET runtime, and there is no ZIP to extract.')
$architectureMarker = 'Both target ordinary Intel or AMD x64 Windows.'

$recommendedIndex = $normalizedContent.IndexOf(
    $recommendedMarker,
    [StringComparison]::Ordinal)
if ($recommendedIndex -lt 0) {
    throw "README must identify ScreenFix-Windows-x64.exe as the recommended smaller self-contained download"
}

$fallbackIndex = $normalizedContent.IndexOf(
    $fallbackMarker,
    [StringComparison]::Ordinal)
if ($fallbackIndex -lt 0) {
    throw "README must identify ScreenFix-Windows-x64-uncompressed.exe as the behavior-identical uncompressed fallback for startup or extraction trouble"
}

if ($recommendedIndex -gt $fallbackIndex) {
    throw "README must name the recommended Windows download before the fallback"
}

if (-not $normalizedContent.Contains(
        $runtimeMarker,
        [StringComparison]::Ordinal)) {
    throw "README must state that neither Windows download needs a separate .NET runtime and there is no ZIP to extract"
}

if (-not $normalizedContent.Contains(
        $architectureMarker,
        [StringComparison]::Ordinal)) {
    throw "README must state that both downloads target ordinary Intel or AMD x64 Windows"
}

if ($content.Contains(
        'ScreenFix-windows-x64.zip',
        [StringComparison]::OrdinalIgnoreCase)) {
    throw "README must not name the obsolete ScreenFix-windows-x64.zip download"
}

if ([Text.RegularExpressions.Regex]::IsMatch(
        $content,
        '(?<![A-Za-z0-9-])ScreenFix\.exe(?![A-Za-z0-9-])',
        [Text.RegularExpressions.RegexOptions]::CultureInvariant)) {
    throw "README must not instruct users to download or run bare ScreenFix.exe"
}

Write-Output "Windows download documentation is current."
