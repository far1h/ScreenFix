param(
    [string]$OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $PSScriptRoot "../artifacts/windows/win-x64"
}

$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$outputItem = Get-Item `
    -LiteralPath $OutputDirectory `
    -Force `
    -ErrorAction SilentlyContinue
if ($null -eq $outputItem `
    -or $outputItem -isnot [IO.DirectoryInfo] `
    -or ($outputItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    throw "package directory does not exist"
}

$entries = @(Get-ChildItem -LiteralPath $OutputDirectory -Force)
$files = @($entries | Where-Object {
    $_ -is [IO.FileInfo] `
        -and -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)
})
if ($entries.Count -ne 1 -or $files.Count -ne 1) {
    throw "package must contain exactly one regular file; found $($files.Count)"
}

$executable = $files[0]
if ($executable.Name -cne "ScreenFix.exe") {
    throw "package file must be named ScreenFix.exe"
}

& (Join-Path $PSScriptRoot "assert-win-x64-executable.ps1") `
    -Executable $executable.FullName `
    -ExpectedFileName "ScreenFix.exe"
