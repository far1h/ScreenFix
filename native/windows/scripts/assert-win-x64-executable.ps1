param(
    [Parameter(Mandatory = $true)]
    [string]$Executable,
    [Parameter(Mandatory = $true)]
    [string]$ExpectedFileName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Executable) `
    -or -not [IO.Path]::IsPathFullyQualified($Executable)) {
    throw "executable path must be absolute"
}
if ([string]::IsNullOrWhiteSpace($ExpectedFileName) `
    -or [IO.Path]::GetFileName($ExpectedFileName) -cne $ExpectedFileName) {
    throw "expected executable filename must be one exact filename"
}

$Executable = [IO.Path]::GetFullPath($Executable)
if ([IO.Path]::GetFileName($Executable) -cne $ExpectedFileName) {
    throw "executable file must be named $ExpectedFileName"
}

$executableFile = Get-Item `
    -LiteralPath $Executable `
    -Force `
    -ErrorAction SilentlyContinue
if ($null -eq $executableFile `
    -or $executableFile -isnot [IO.FileInfo] `
    -or ($executableFile.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    throw "executable must be one regular non-reparse file"
}
if ($executableFile.Name -cne $ExpectedFileName) {
    throw "executable file must be named $ExpectedFileName"
}
if ($executableFile.Length -le 0) {
    throw "executable is empty"
}

$fileHash = Get-FileHash -LiteralPath $Executable -Algorithm SHA256
if ([string]::IsNullOrWhiteSpace($fileHash.Hash)) {
    throw "executable SHA-256 could not be computed"
}

$stream = [IO.File]::Open(
    $Executable,
    [IO.FileMode]::Open,
    [IO.FileAccess]::Read,
    [IO.FileShare]::Read)
try {
    $dosHeader = [byte[]]::new(64)
    if ($stream.Read($dosHeader, 0, $dosHeader.Length) -lt 2) {
        throw "executable is too small for DOS signature"
    }
    if ($dosHeader[0] -ne 0x4d -or $dosHeader[1] -ne 0x5a) {
        throw "executable does not have an MZ signature"
    }
    if ($stream.Length -lt $dosHeader.Length) {
        throw "executable is too small for PE offset"
    }

    $peOffset = [int]$dosHeader[0x3c] `
        -bor ([int]$dosHeader[0x3d] -shl 8) `
        -bor ([int]$dosHeader[0x3e] -shl 16) `
        -bor ([int]$dosHeader[0x3f] -shl 24)
    if ($peOffset -lt 0 -or $peOffset -gt $stream.Length - 24) {
        throw "executable PE header is outside the file"
    }

    $stream.Position = $peOffset
    $peHeader = [byte[]]::new(24)
    if ($stream.Read($peHeader, 0, $peHeader.Length) -ne $peHeader.Length) {
        throw "executable PE header is outside the file"
    }
    if ($peHeader[0] -ne 0x50 `
        -or $peHeader[1] -ne 0x45 `
        -or $peHeader[2] -ne 0 `
        -or $peHeader[3] -ne 0) {
        throw "executable does not have a PE signature"
    }

    $machine = [int]$peHeader[4] -bor ([int]$peHeader[5] -shl 8)
    if ($machine -ne 0x8664) {
        throw ("executable machine is not AMD64: 0x{0:x4}" -f $machine)
    }

    $optionalHeaderSize = [int]$peHeader[20] `
        -bor ([int]$peHeader[21] -shl 8)
    if ($optionalHeaderSize -lt 2) {
        throw "executable PE optional header is missing"
    }
    if ($optionalHeaderSize -gt $stream.Length - $stream.Position) {
        throw "executable PE optional header is truncated"
    }

    $subsystemOffset = 68
    if ($optionalHeaderSize -lt $subsystemOffset + 2) {
        throw "executable optional header does not contain a subsystem"
    }

    $optionalHeader = [byte[]]::new($subsystemOffset + 2)
    if ($stream.Read($optionalHeader, 0, $optionalHeader.Length) `
        -ne $optionalHeader.Length) {
        throw "executable PE optional header is truncated"
    }
    $optionalHeaderMagic = [int]$optionalHeader[0] `
        -bor ([int]$optionalHeader[1] -shl 8)
    if ($optionalHeaderMagic -ne 0x20b) {
        throw (
            "executable optional header is not PE32+: 0x{0:x4}" `
                -f $optionalHeaderMagic)
    }

    $subsystem = [int]$optionalHeader[$subsystemOffset] `
        -bor ([int]$optionalHeader[$subsystemOffset + 1] -shl 8)
    if ($subsystem -ne 2) {
        throw "executable subsystem is not Windows GUI: $subsystem"
    }
}
finally {
    $stream.Dispose()
}

Write-Output "$ExpectedFileName sha256=$($fileHash.Hash)"
