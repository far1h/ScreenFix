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

    $bytes[0x98] = 0x0b
    $bytes[0x99] = 0x02
    $bytes[0xdc] = 0x03
    $bytes[0xdd] = 0
    [IO.File]::WriteAllBytes((Join-Path $directory "ScreenFix.exe"), $bytes)

    $rejection = $null
    try {
        & $assertion -OutputDirectory $directory
    }
    catch {
        $rejection = $_.Exception.Message
    }

    if ($null -eq $rejection) {
        throw "console subsystem executable was accepted"
    }

    if ($rejection -cne "executable subsystem is not Windows GUI: 3") {
        throw "unexpected rejection: $rejection"
    }

    $bytes[0xdc] = 0x02
    [IO.File]::WriteAllBytes((Join-Path $directory "ScreenFix.exe"), $bytes)
    & $assertion -OutputDirectory $directory

    $bytes[0x84] = 0x4c
    $bytes[0x85] = 0x01
    [IO.File]::WriteAllBytes((Join-Path $directory "ScreenFix.exe"), $bytes)

    $rejection = $null
    try {
        & $assertion -OutputDirectory $directory
    }
    catch {
        $rejection = $_.Exception.Message
    }

    if ($rejection -cne "executable machine is not AMD64: 0x014c") {
        throw "unexpected wrong-machine rejection: $rejection"
    }

    [IO.File]::WriteAllText((Join-Path $directory "companion.txt"), "unexpected")
    $rejection = $null
    try {
        & $assertion -OutputDirectory $directory
    }
    catch {
        $rejection = $_.Exception.Message
    }

    if ($rejection -cne "package must contain exactly one regular file; found 2") {
        throw "unexpected companion-file rejection: $rejection"
    }

    Remove-Item -LiteralPath (Join-Path $directory "companion.txt")
    [IO.File]::WriteAllBytes(
        (Join-Path $directory "ScreenFix.exe"),
        [byte[]]::new(0))
    $rejection = $null
    try {
        & $assertion -OutputDirectory $directory
    }
    catch {
        $rejection = $_.Exception.Message
    }

    if ($rejection -cne "executable is empty") {
        throw "unexpected empty-file rejection: $rejection"
    }
}
finally {
    if (Test-Path -LiteralPath $directory) {
        Remove-Item -LiteralPath $directory -Recurse -Force
    }
}

Write-Output "package assertion regression tests passed"
