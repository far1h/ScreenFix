param(
    [string]$OutputDirectory
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $PSScriptRoot "../artifacts/windows/win-x64"
}

$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
    throw "package directory does not exist"
}

$files = @(Get-ChildItem -LiteralPath $OutputDirectory -File -Recurse)
if ($files.Count -ne 1) {
    throw "package must contain exactly one regular file; found $($files.Count)"
}

$executable = $files[0]
if ($executable.Name -cne "ScreenFix.exe") {
    throw "package file must be named ScreenFix.exe"
}

$bytes = [IO.File]::ReadAllBytes($executable.FullName)
if ($bytes.Length -lt 2) {
    throw "executable is too small for DOS signature"
}

if ($bytes[0] -ne 0x4d -or $bytes[1] -ne 0x5a) {
    throw "executable does not have an MZ signature"
}

if ($bytes.Length -lt 0x40) {
    throw "executable is too small for PE offset"
}

$peOffset = [int]$bytes[0x3c] `
    -bor ([int]$bytes[0x3d] -shl 8) `
    -bor ([int]$bytes[0x3e] -shl 16) `
    -bor ([int]$bytes[0x3f] -shl 24)
if ($peOffset -lt 0 -or $peOffset -gt $bytes.Length - 6) {
    throw "executable PE offset is outside the file"
}

$machine = [int]$bytes[$peOffset + 4] -bor ([int]$bytes[$peOffset + 5] -shl 8)
if ($machine -ne 0x8664) {
    throw ("executable machine is not AMD64: 0x{0:x4}" -f $machine)
}
