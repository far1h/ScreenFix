Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$assertion = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "assert-win-x64-release.ps1"))
$executableAssertion = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "assert-win-x64-executable.ps1"))
$publishScript = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "publish-win-x64.ps1"))
$workflow = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "../../../.github/workflows/windows-native.yml"))
$documentationAssertion = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "assert-windows-download-docs.ps1"))
$readme = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "../../../README.md"))
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) (
    "ScreenFix.ReleaseAssertionTests." + [Guid]::NewGuid().ToString("N"))
$recommendedName = "ScreenFix-Windows-x64.exe"
$fallbackName = "ScreenFix-Windows-x64-uncompressed.exe"
$passedControls = 0

function Write-ValidExecutable {
    param(
        [string]$Path,
        [int]$Length
    )

    if ($Length -lt 256) {
        throw "synthetic executable length must be at least 256 bytes"
    }

    $bytes = [byte[]]::new($Length)
    $bytes[0] = 0x4d
    $bytes[1] = 0x5a
    $bytes[0x3c] = 0x80
    $bytes[0x80] = 0x50
    $bytes[0x81] = 0x45
    $bytes[0x84] = 0x64
    $bytes[0x85] = 0x86
    $bytes[0x94] = 0x68
    $bytes[0x98] = 0x0b
    $bytes[0x99] = 0x02
    $bytes[0xdc] = 0x02
    [IO.File]::WriteAllBytes($Path, $bytes)
}

function New-ReleaseFixture {
    param(
        [string]$Name,
        [int]$RecommendedLength = 3200,
        [int]$FallbackLength = 4000
    )

    $directory = Join-Path $temporaryRoot $Name
    [void](New-Item -ItemType Directory -Path $directory)
    Write-ValidExecutable `
        -Path (Join-Path $directory $recommendedName) `
        -Length $RecommendedLength
    Write-ValidExecutable `
        -Path (Join-Path $directory $fallbackName) `
        -Length $FallbackLength
    return [IO.Path]::GetFullPath($directory)
}

function Assert-Rejection {
    param(
        [string]$Name,
        [string]$Directory,
        [string]$Expected
    )

    $diagnostic = $null
    try {
        & $assertion -ReleaseDirectory $Directory
    }
    catch {
        $diagnostic = $_.Exception.Message
    }

    if ($diagnostic -cne $Expected) {
        throw "$Name returned an unexpected diagnostic. Expected: $Expected Actual: $diagnostic"
    }

    $script:passedControls++
}

try {
    [void](New-Item -ItemType Directory -Path $temporaryRoot)

    $executableAssertionSource = [IO.File]::ReadAllText($executableAssertion)
    if (-not $executableAssertionSource.Contains(
            '$executableFile.Name -cne $ExpectedFileName')) {
        throw "executable assertion must compare the filesystem filename case-sensitively"
    }
    $passedControls++

    $publishSource = [IO.File]::ReadAllText($publishScript)
    foreach ($requiredPublishMarker in @(
            '[string]$DotnetPath',
            '[string]$ExternalDotnetPath',
            '[switch]$MeasureStartup',
            '--artifacts-path',
            'build/uncompressed',
            'build/compressed',
            'obj/uncompressed',
            'obj/compressed',
            '-p:EnableCompressionInSingleFile=$compression',
            'assert-pinned-win-x64-toolchain-preflight.ps1',
            'assert-pinned-win-x64-toolchain.ps1',
            'assert-win-x64-release.ps1',
            'WindowsReleaseTransaction.psm1',
            'Invoke-WindowsReleaseTransaction',
            'ScreenFix-Windows-x64.exe',
            'ScreenFix-Windows-x64-uncompressed.exe')) {
        if (-not $publishSource.Contains($requiredPublishMarker)) {
            throw "publish script dual packaging contract is incomplete: $requiredPublishMarker"
        }
    }
    if ($publishSource.Contains('Remove-GeneratedRoot -Path $releaseRoot')) {
        throw "publish script must not delete the existing final release before promotion"
    }
    $passedControls++

    $workflowSource = [IO.File]::ReadAllText($workflow)
    foreach ($requiredWorkflowMarker in @(
            'actions/upload-artifact@v7',
            'actions/download-artifact@v8',
            'screenfix-windows-x64-${{ env.SCREENFIX_SOURCE_SHA }}',
            'if-no-files-found: error',
            'ScreenFix-Windows-x64.exe',
            'ScreenFix-Windows-x64-uncompressed.exe',
            'assert-win-x64-release.ps1')) {
        if (-not $workflowSource.Contains($requiredWorkflowMarker)) {
            throw "Windows workflow artifact contract is incomplete: $requiredWorkflowMarker"
        }
    }
    $passedControls++

    $documentationOutput = @(& $documentationAssertion -ReadmePath $readme)
    if (($documentationOutput -join "`n") -cne `
        "Windows download documentation is current.") {
        throw "Windows release documentation assertion returned unexpected output"
    }
    $passedControls++

    $missingRecommended = New-ReleaseFixture -Name "missing-recommended"
    Remove-Item -LiteralPath (Join-Path $missingRecommended $recommendedName)
    Assert-Rejection `
        -Name "missing recommended asset" `
        -Directory $missingRecommended `
        -Expected "release directory is missing $recommendedName"

    $missingFallback = New-ReleaseFixture -Name "missing-fallback"
    Remove-Item -LiteralPath (Join-Path $missingFallback $fallbackName)
    Assert-Rejection `
        -Name "missing fallback asset" `
        -Directory $missingFallback `
        -Expected "release directory is missing $fallbackName"

    $legacy = New-ReleaseFixture -Name "legacy"
    Write-ValidExecutable -Path (Join-Path $legacy "ScreenFix.exe") -Length 256
    Assert-Rejection `
        -Name "legacy asset" `
        -Directory $legacy `
        -Expected "release directory contains unexpected entry: ScreenFix.exe"

    $companion = New-ReleaseFixture -Name "companion"
    [IO.File]::WriteAllText((Join-Path $companion "notes.txt"), "unexpected")
    Assert-Rejection `
        -Name "companion file" `
        -Directory $companion `
        -Expected "release directory contains unexpected entry: notes.txt"

    $directoryAsset = New-ReleaseFixture -Name "directory-asset"
    Remove-Item -LiteralPath (Join-Path $directoryAsset $recommendedName)
    [void](New-Item -ItemType Directory -Path (Join-Path $directoryAsset $recommendedName))
    Assert-Rejection `
        -Name "directory asset" `
        -Directory $directoryAsset `
        -Expected "release asset must be one regular non-reparse nonempty file: $recommendedName"

    $emptyAsset = New-ReleaseFixture -Name "empty-asset"
    [IO.File]::WriteAllBytes(
        (Join-Path $emptyAsset $recommendedName),
        [byte[]]::new(0))
    Assert-Rejection `
        -Name "empty asset" `
        -Directory $emptyAsset `
        -Expected "release asset must be one regular non-reparse nonempty file: $recommendedName"

    $reparseAsset = New-ReleaseFixture -Name "reparse-asset"
    $reparseTarget = Join-Path $temporaryRoot "recommended-target.exe"
    Move-Item `
        -LiteralPath (Join-Path $reparseAsset $recommendedName) `
        -Destination $reparseTarget
    try {
        [void](New-Item `
            -ItemType SymbolicLink `
            -Path (Join-Path $reparseAsset $recommendedName) `
            -Target $reparseTarget `
            -ErrorAction Stop)
        Assert-Rejection `
            -Name "reparse asset" `
            -Directory $reparseAsset `
            -Expected "release asset must be one regular non-reparse nonempty file: $recommendedName"
    }
    catch [System.UnauthorizedAccessException] {
        Write-Warning "reparse asset control skipped because symlink creation is unavailable"
    }

    $swapped = New-ReleaseFixture `
        -Name "swapped" `
        -RecommendedLength 4000 `
        -FallbackLength 3200
    Assert-Rejection `
        -Name "swapped public roles" `
        -Directory $swapped `
        -Expected "compressed release asset must be smaller than uncompressed release asset"

    $notSmaller = New-ReleaseFixture `
        -Name "not-smaller" `
        -RecommendedLength 4000 `
        -FallbackLength 4000
    Assert-Rejection `
        -Name "candidate not smaller" `
        -Directory $notSmaller `
        -Expected "compressed release asset must be smaller than uncompressed release asset"

    $overLimit = New-ReleaseFixture `
        -Name "over-limit" `
        -RecommendedLength 3201 `
        -FallbackLength 4000
    Assert-Rejection `
        -Name "candidate over eighty percent" `
        -Directory $overLimit `
        -Expected "compressed release asset exceeds 80 percent of uncompressed release asset: 3201 > 3200"

    $valid = New-ReleaseFixture -Name "valid"
    $recommendedPath = Join-Path $valid $recommendedName
    $fallbackPath = Join-Path $valid $fallbackName
    $alternateCasePath = Join-Path $valid $recommendedName.ToUpperInvariant()
    $alternateCaseItem = Get-Item `
        -LiteralPath $alternateCasePath `
        -Force `
        -ErrorAction SilentlyContinue
    if ($null -ne $alternateCaseItem `
        -and $alternateCaseItem.Name -cne $recommendedName.ToUpperInvariant()) {
        $alternateCaseDiagnostic = $null
        try {
            & $executableAssertion `
                -Executable $alternateCasePath `
                -ExpectedFileName $recommendedName.ToUpperInvariant()
        }
        catch {
            $alternateCaseDiagnostic = $_.Exception.Message
        }
        $expectedAlternateDiagnostic = (
            "executable file must be named " + $recommendedName.ToUpperInvariant())
        if ($alternateCaseDiagnostic -cne $expectedAlternateDiagnostic) {
            throw "filesystem filename casing was not enforced"
        }
        $passedControls++
    }

    $recommendedHash = (Get-FileHash `
        -LiteralPath $recommendedPath `
        -Algorithm SHA256).Hash
    $fallbackHash = (Get-FileHash `
        -LiteralPath $fallbackPath `
        -Algorithm SHA256).Hash
    $firstOutput = @(& $assertion -ReleaseDirectory $valid)
    $secondOutput = @(& $assertion -ReleaseDirectory $valid)
    if (($firstOutput -join "`n") -cne ($secondOutput -join "`n")) {
        throw "release assertion output is not repeatable"
    }

    $renderedOutput = $firstOutput -join [Environment]::NewLine
    foreach ($expectedLine in @(
            "$recommendedName size=3200 sha256=$recommendedHash",
            "$fallbackName size=4000 sha256=$fallbackHash",
            "compressed reduction=20.00 percent")) {
        if (-not $renderedOutput.Contains($expectedLine)) {
            throw "release assertion output is missing: $expectedLine"
        }
    }

    $afterRecommendedHash = (Get-FileHash `
        -LiteralPath $recommendedPath `
        -Algorithm SHA256).Hash
    $afterFallbackHash = (Get-FileHash `
        -LiteralPath $fallbackPath `
        -Algorithm SHA256).Hash
    if ($afterRecommendedHash -cne $recommendedHash `
        -or $afterFallbackHash -cne $fallbackHash) {
        throw "release assertion modified a staged executable"
    }

    $passedControls++
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}

Write-Output "release assertion regression tests passed ($passedControls controls)"
