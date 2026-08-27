param(
    [string]$OutputDirectory,
    [string]$CanonicalIcon
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $PSScriptRoot "../artifacts/windows/win-x64"
}

if ([string]::IsNullOrWhiteSpace($CanonicalIcon)) {
    $CanonicalIcon = Join-Path $PSScriptRoot "../src/ScreenFix.App/Resources/ScreenFix.ico"
}

$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
    throw "package directory does not exist"
}

$CanonicalIcon = [IO.Path]::GetFullPath($CanonicalIcon)
if (-not (Test-Path -LiteralPath $CanonicalIcon -PathType Leaf)) {
    throw "canonical icon must be one regular nonempty file"
}

$canonicalIconFile = Get-Item -LiteralPath $CanonicalIcon
if ($canonicalIconFile.Length -eq 0 `
    -or ($canonicalIconFile.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    throw "canonical icon must be one regular nonempty file"
}

if (-not ("ScreenFix.Package.ByteSearch" -as [type])) {
    Add-Type -TypeDefinition @'
using System;

namespace ScreenFix.Package
{
    public static class ByteSearch
    {
        public static bool Contains(byte[] source, byte[] pattern)
        {
            return source.AsSpan().IndexOf(pattern) >= 0;
        }
    }
}
'@
}

$files = @(Get-ChildItem -LiteralPath $OutputDirectory -File -Recurse)
if ($files.Count -ne 1) {
    throw "package must contain exactly one regular file; found $($files.Count)"
}

$executable = $files[0]
if ($executable.Name -cne "ScreenFix.exe") {
    throw "package file must be named ScreenFix.exe"
}

if ($executable.Length -eq 0) {
    throw "executable is empty"
}

$fileHash = Get-FileHash -LiteralPath $executable.FullName -Algorithm SHA256
if ([string]::IsNullOrWhiteSpace($fileHash.Hash)) {
    throw "executable SHA-256 could not be computed"
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
if ($peOffset -lt 0 -or $peOffset -gt $bytes.Length - 24) {
    throw "executable PE header is outside the file"
}

if ($bytes[$peOffset] -ne 0x50 `
    -or $bytes[$peOffset + 1] -ne 0x45 `
    -or $bytes[$peOffset + 2] -ne 0 `
    -or $bytes[$peOffset + 3] -ne 0) {
    throw "executable does not have a PE signature"
}

$machine = [int]$bytes[$peOffset + 4] -bor ([int]$bytes[$peOffset + 5] -shl 8)
if ($machine -ne 0x8664) {
    throw ("executable machine is not AMD64: 0x{0:x4}" -f $machine)
}

$optionalHeaderSize = [int]$bytes[$peOffset + 20] `
    -bor ([int]$bytes[$peOffset + 21] -shl 8)
if ($optionalHeaderSize -lt 2) {
    throw "executable PE optional header is missing"
}

$optionalHeaderOffset = $peOffset + 24
if ($optionalHeaderSize -gt $bytes.Length - $optionalHeaderOffset) {
    throw "executable PE optional header is truncated"
}

$optionalHeaderMagic = [int]$bytes[$optionalHeaderOffset] `
    -bor ([int]$bytes[$optionalHeaderOffset + 1] -shl 8)
if ($optionalHeaderMagic -ne 0x20b) {
    throw ("executable optional header is not PE32+: 0x{0:x4}" -f $optionalHeaderMagic)
}

$subsystemOffset = 68
if ($optionalHeaderSize -lt $subsystemOffset + 2) {
    throw "executable optional header does not contain a subsystem"
}

$subsystem = [int]$bytes[$optionalHeaderOffset + $subsystemOffset] `
    -bor ([int]$bytes[$optionalHeaderOffset + $subsystemOffset + 1] -shl 8)
if ($subsystem -ne 2) {
    throw "executable subsystem is not Windows GUI: $subsystem"
}

$canonicalIconBytes = [IO.File]::ReadAllBytes($canonicalIconFile.FullName)
if (-not [ScreenFix.Package.ByteSearch]::Contains($bytes, $canonicalIconBytes)) {
    throw "executable does not contain the canonical managed ScreenFix icon"
}
