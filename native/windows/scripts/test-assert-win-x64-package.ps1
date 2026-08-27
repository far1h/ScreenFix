$ErrorActionPreference = "Stop"

$assertion = Join-Path $PSScriptRoot "assert-win-x64-package.ps1"
$canonicalIcon = Join-Path $PSScriptRoot "../src/ScreenFix.App/Resources/ScreenFix.ico"
$canonicalIconBytes = [IO.File]::ReadAllBytes($canonicalIcon)
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
    $validBytes = [byte[]]::new($bytes.Length + $canonicalIconBytes.Length)
    [Array]::Copy($bytes, 0, $validBytes, 0, $bytes.Length)
    [Array]::Copy(
        $canonicalIconBytes,
        0,
        $validBytes,
        $bytes.Length,
        $canonicalIconBytes.Length)
    [IO.File]::WriteAllBytes((Join-Path $directory "ScreenFix.exe"), $validBytes)
    & $assertion -OutputDirectory $directory

    $mismatchedBytes = [byte[]]$validBytes.Clone()
    $mismatchedBytes[$mismatchedBytes.Length - 1] = `
        $mismatchedBytes[$mismatchedBytes.Length - 1] -bxor 0xff
    [IO.File]::WriteAllBytes((Join-Path $directory "ScreenFix.exe"), $mismatchedBytes)

    $rejection = $null
    try {
        & $assertion -OutputDirectory $directory
    }
    catch {
        $rejection = $_.Exception.Message
    }

    if ($null -eq $rejection) {
        throw "executable with mismatched canonical icon was accepted"
    }

    if ($rejection -cne "executable does not contain the canonical managed ScreenFix icon") {
        throw "unexpected canonical-icon rejection: $rejection"
    }

    $bytes[0x84] = 0x4c
    $bytes[0x85] = 0x01
    [Array]::Copy($bytes, 0, $validBytes, 0, $bytes.Length)
    [IO.File]::WriteAllBytes((Join-Path $directory "ScreenFix.exe"), $validBytes)

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

if ($IsWindows) {
    $project = [IO.Path]::GetFullPath(
        (Join-Path $PSScriptRoot "../tests/ScreenFix.Windows.Tests/ScreenFix.Windows.Tests.csproj"))
    $appProject = [IO.Path]::GetFullPath(
        (Join-Path $PSScriptRoot "../src/ScreenFix.App/ScreenFix.App.csproj"))
    $temporaryRoot = Join-Path (
        [IO.Path]::GetTempPath()) (
        "screenfix-no-app-icon-" + [Guid]::NewGuid().ToString("N"))
    $temporaryArtifacts = Join-Path $temporaryRoot "negative-artifacts"
    $temporaryPublish = Join-Path $temporaryRoot "negative-publish"
    $temporaryPositivePublish = Join-Path $temporaryRoot "positive-publish"
    $previousExecutable = $env:SCREENFIX_PUBLISHED_EXE
    $previousCanonical = $env:SCREENFIX_CANONICAL_ICO
    try {
        & dotnet build $project -c Release
        if ($LASTEXITCODE -ne 0) {
            throw "Windows test build failed"
        }

        & dotnet publish $appProject `
            -c Release -r win-x64 --self-contained true `
            --artifacts-path $temporaryArtifacts `
            -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true `
            -p:EnableCompressionInSingleFile=false `
            -p:PublishTrimmed=false -p:UseAppHost=true -p:ApplicationIcon= `
            -o $temporaryPublish
        if ($LASTEXITCODE -ne 0) {
            throw "negative-control publish failed"
        }

        $env:SCREENFIX_PUBLISHED_EXE = Join-Path $temporaryPublish "ScreenFix.exe"
        $env:SCREENFIX_CANONICAL_ICO = [IO.Path]::GetFullPath($canonicalIcon)
        & dotnet test $project -c Release --no-build `
            --filter "FullyQualifiedName~PublishedExecutable_ContainsCanonicalManagedIconBytes"
        if ($LASTEXITCODE -ne 0) {
            throw "iconless apphost lost the required managed ScreenFix icon"
        }

        $nativeIconOutput = & dotnet test $project -c Release --no-build `
            --logger "console;verbosity=normal" `
            --filter "FullyQualifiedName~PublishedExecutable_ContainsEveryNativeIconFrame" 2>&1
        $nativeIconExit = $LASTEXITCODE
        $nativeIconOutput | Write-Output
        if ($nativeIconExit -eq 0) {
            throw "iconless apphost was accepted"
        }

        $nativeIconDiagnostic = [regex]::Replace(
            ($nativeIconOutput -join [Environment]::NewLine),
            "\s+",
            " ")
        if (-not $nativeIconDiagnostic.Contains(
                "PublishedExecutable_ContainsEveryNativeIconFrame") `
            -or -not $nativeIconDiagnostic.Contains(
                "does not contain an RT_GROUP_ICON with the exact Screen Patch frame set and payloads")) {
            throw "iconless apphost failed for an unexpected reason"
        }

        & dotnet publish $appProject `
            -c Release -r win-x64 --self-contained true `
            -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true `
            -p:EnableCompressionInSingleFile=false `
            -p:PublishTrimmed=false -p:UseAppHost=true `
            -p:DebugType=None -p:DebugSymbols=false `
            -o $temporaryPositivePublish
        if ($LASTEXITCODE -ne 0) {
            throw "positive-control publish failed"
        }

        $env:SCREENFIX_PUBLISHED_EXE = Join-Path $temporaryPositivePublish "ScreenFix.exe"
        & dotnet test $project -c Release --no-build `
            --filter "FullyQualifiedName~PublishedExecutable_ContainsEveryNativeIconFrame"
        if ($LASTEXITCODE -ne 0) {
            throw "default apphost remained iconless after the negative control"
        }
    }
    finally {
        $env:SCREENFIX_PUBLISHED_EXE = $previousExecutable
        $env:SCREENFIX_CANONICAL_ICO = $previousCanonical
        if (Test-Path -LiteralPath $temporaryRoot) {
            Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
        }
    }
}

Write-Output "package assertion regression tests passed"
