$ErrorActionPreference = "Stop"

$assertion = Join-Path $PSScriptRoot "assert-win-x64-package.ps1"
$directory = Join-Path (
    [IO.Path]::GetTempPath()) (
    "ScreenFix.PackageTests." + [Guid]::NewGuid().ToString("N"))

try {
    [void](New-Item -ItemType Directory -Path $directory)
    $bytes = [byte[]]::new(256)
    $bytes[0] = 0x4d
    $bytes[1] = 0x5a
    $bytes[0x3c] = 0x80
    $bytes[0x84] = 0x64
    $bytes[0x85] = 0x86
    [IO.File]::WriteAllBytes((Join-Path $directory "ScreenFix.exe"), $bytes)

    $rejection = $null
    try {
        & $assertion -OutputDirectory $directory
    }
    catch {
        $rejection = $_.Exception.Message
    }

    if ($null -eq $rejection) {
        throw "crafted non-PE executable was accepted"
    }

    if ($rejection -cne "executable does not have a PE signature") {
        throw "unexpected rejection: $rejection"
    }

    $bytes[0x80] = 0x50
    $bytes[0x81] = 0x45
    $bytes[0x82] = 0
    $bytes[0x83] = 0
    $bytes[0x94] = 0x68
    [IO.File]::WriteAllBytes((Join-Path $directory "ScreenFix.exe"), $bytes)

    $rejection = $null
    try {
        & $assertion -OutputDirectory $directory
    }
    catch {
        $rejection = $_.Exception.Message
    }

    if ($null -eq $rejection) {
        throw "crafted non-PE32+ executable was accepted"
    }

    if ($rejection -cne "executable optional header is not PE32+: 0x0000") {
        throw "unexpected rejection: $rejection"
    }
}
finally {
    if (Test-Path -LiteralPath $directory) {
        Remove-Item -LiteralPath $directory -Recurse -Force
    }
}

Write-Output "package assertion regression tests passed"
