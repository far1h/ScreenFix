param(
    [Parameter(Mandatory = $true)]
    [string]$DotnetPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($DotnetPath) `
    -or -not [IO.Path]::IsPathFullyQualified($DotnetPath)) {
    throw "dotnet path must be one absolute regular non-reparse executable file"
}

$dotnetPath = [IO.Path]::GetFullPath($DotnetPath)
$dotnetFile = Get-Item `
    -LiteralPath $dotnetPath `
    -Force `
    -ErrorAction SilentlyContinue
if ($null -eq $dotnetFile `
    -or $dotnetFile -isnot [IO.FileInfo] `
    -or $dotnetFile.Length -le 0 `
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
    $mode = [int][IO.File]::GetUnixFileMode($dotnetPath)
    if (($mode -band $executeMask) -eq 0) {
        throw "dotnet path must be one absolute regular non-reparse executable file"
    }
}

$project = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "../src/ScreenFix.App/ScreenFix.App.csproj"))
$output = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "../artifacts/windows/win-x64"))
$assertion = Join-Path $PSScriptRoot "assert-win-x64-package.ps1"

if (Test-Path -LiteralPath $output) {
    Remove-Item -LiteralPath $output -Recurse -Force
}

$publishOutput = & $dotnetPath publish $project `
    -c Release `
    -r win-x64 `
    --self-contained true `
    -o $output `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -p:EnableCompressionInSingleFile=false `
    -p:PublishTrimmed=false `
    -p:DebugType=None `
    -p:DebugSymbols=false `
    -p:UseAppHost=true

if ($LASTEXITCODE -ne 0) {
    $details = $publishOutput -join [Environment]::NewLine
    throw "dotnet publish failed with exit code $LASTEXITCODE`n$details"
}

& $assertion -OutputDirectory $output
& (Join-Path $PSScriptRoot "test-windows-native.ps1") `
    -DotnetPath $dotnetPath `
    -PublishedExecutable (Join-Path $output "ScreenFix.exe") `
    -ExpectedCompression uncompressed

$artifact = Get-Item -LiteralPath (Join-Path $output "ScreenFix.exe")
Write-Output ("{0} ({1} bytes)" -f $artifact.FullName, $artifact.Length)
