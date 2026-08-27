Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$module = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "WindowsReleaseTransaction.psm1"))
$releaseAssertion = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "assert-win-x64-release.ps1"))
$temporaryBase = if (-not $IsWindows `
    -and (Test-Path -LiteralPath "/private/tmp" -PathType Container)) {
    "/private/tmp"
}
else {
    [IO.Path]::GetTempPath()
}
$temporaryRoot = Join-Path $temporaryBase (
    "ScreenFix.ReleaseTransactionTests." + [Guid]::NewGuid().ToString("N"))
$recommendedName = "ScreenFix-Windows-x64.exe"
$fallbackName = "ScreenFix-Windows-x64-uncompressed.exe"
$passedControls = 0

Import-Module $module -Force

function Write-ValidExecutable {
    param(
        [string]$Path,
        [int]$Length,
        [byte]$Marker = 0
    )

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
    $bytes[$Length - 1] = $Marker
    [IO.File]::WriteAllBytes($Path, $bytes)
}

function New-TransactionFixture {
    param([string]$Name)

    $parent = Join-Path $temporaryRoot $Name
    $release = Join-Path $parent "release"
    $roundOne = Join-Path $parent "round-one"
    $roundTwo = Join-Path $parent "round-two"
    [void](New-Item -ItemType Directory -Path $release)
    [void](New-Item -ItemType Directory -Path $roundOne)
    [void](New-Item -ItemType Directory -Path $roundTwo)
    $previous = Join-Path $release "previous.bin"
    [IO.File]::WriteAllText($previous, "previous-$Name")

    $roundOneCompressed = Join-Path $roundOne "ScreenFix.exe"
    $roundOneUncompressed = Join-Path $roundOne "ScreenFix-uncompressed.exe"
    $roundTwoCompressed = Join-Path $roundTwo "ScreenFix.exe"
    $roundTwoUncompressed = Join-Path $roundTwo "ScreenFix-uncompressed.exe"
    Write-ValidExecutable -Path $roundOneCompressed -Length 3200
    Write-ValidExecutable -Path $roundOneUncompressed -Length 4000
    Write-ValidExecutable -Path $roundTwoCompressed -Length 3200
    Write-ValidExecutable -Path $roundTwoUncompressed -Length 4000

    return [pscustomobject]@{
        Parent = [IO.Path]::GetFullPath($parent)
        Release = [IO.Path]::GetFullPath($release)
        Previous = [IO.Path]::GetFullPath($previous)
        PreviousHash = (Get-FileHash -LiteralPath $previous -Algorithm SHA256).Hash
        RoundOneCompressed = [IO.Path]::GetFullPath($roundOneCompressed)
        RoundOneUncompressed = [IO.Path]::GetFullPath($roundOneUncompressed)
        RoundTwoCompressed = [IO.Path]::GetFullPath($roundTwoCompressed)
        RoundTwoUncompressed = [IO.Path]::GetFullPath($roundTwoUncompressed)
    }
}

function Assert-OldReleasePreserved {
    param([object]$Fixture)

    $entries = @(Get-ChildItem -LiteralPath $Fixture.Release -Force)
    if ($entries.Count -ne 1 `
        -or $entries[0].Name -cne "previous.bin" `
        -or (Get-FileHash -LiteralPath $entries[0].FullName -Algorithm SHA256).Hash `
            -cne $Fixture.PreviousHash) {
        throw "existing final release was not preserved byte-for-byte"
    }
}

function Assert-NoTransactionResidue {
    param([object]$Fixture)

    $residue = @(Get-ChildItem -LiteralPath $Fixture.Parent -Force | Where-Object {
        $_.Name -match '^release\.(candidate|backup)\.'
    })
    if ($residue.Count -ne 0) {
        throw "release transaction left temporary state: $($residue[0].FullName)"
    }
}

function Invoke-Transaction {
    param(
        [object]$Fixture,
        [scriptblock]$VerifyCandidate,
        [scriptblock]$BuildSecondRound,
        [scriptblock]$CopyFile,
        [scriptblock]$MoveDirectory
    )

    $parameters = @{
        ArtifactsParent = $Fixture.Parent
        ReleaseDirectory = $Fixture.Release
        CompressedSource = $Fixture.RoundOneCompressed
        UncompressedSource = $Fixture.RoundOneUncompressed
        VerifyCandidate = $VerifyCandidate
        BuildSecondRound = $BuildSecondRound
    }
    if ($null -ne $CopyFile) {
        $parameters.CopyFile = $CopyFile
    }
    if ($null -ne $MoveDirectory) {
        $parameters.MoveDirectory = $MoveDirectory
    }

    Invoke-WindowsReleaseTransaction @parameters
}

function Assert-Rejection {
    param(
        [object]$Fixture,
        [scriptblock]$Operation,
        [string]$Expected,
        [string]$Name
    )

    $diagnostic = $null
    try {
        & $Operation
    }
    catch {
        $diagnostic = $_.Exception.Message
    }
    if ($diagnostic -cne $Expected) {
        throw "$Name returned an unexpected diagnostic. Expected: $Expected Actual: $diagnostic"
    }

    Assert-OldReleasePreserved -Fixture $Fixture
    Assert-NoTransactionResidue -Fixture $Fixture
    $script:passedControls++
}

try {
    [void](New-Item -ItemType Directory -Path $temporaryRoot)

    $partialCopy = New-TransactionFixture -Name "partial-copy"
    $copyCount = 0
    $copyOperation = {
        param([string]$Source, [string]$Destination)

        $script:copyCount++
        if ($script:copyCount -eq 2) {
            throw "synthetic second copy failed"
        }
        Copy-Item -LiteralPath $Source -Destination $Destination
    }
    Assert-Rejection `
        -Fixture $partialCopy `
        -Operation {
            Invoke-Transaction `
                -Fixture $partialCopy `
                -VerifyCandidate { param([string]$Directory) } `
                -BuildSecondRound { throw "second round must not run" } `
                -CopyFile $copyOperation
        } `
        -Expected "synthetic second copy failed" `
        -Name "partial second copy"

    $stagedFailure = New-TransactionFixture -Name "staged-verification"
    $secondRoundCalled = $false
    Assert-Rejection `
        -Fixture $stagedFailure `
        -Operation {
            Invoke-Transaction `
                -Fixture $stagedFailure `
                -VerifyCandidate { throw "synthetic staged verification failed" } `
                -BuildSecondRound {
                    $script:secondRoundCalled = $true
                    throw "second round must not run"
                }
        } `
        -Expected "synthetic staged verification failed" `
        -Name "staged verification failure"
    if ($secondRoundCalled) {
        throw "second round ran after staged verification failed"
    }

    $nondeterministic = New-TransactionFixture -Name "nondeterministic"
    Write-ValidExecutable `
        -Path $nondeterministic.RoundTwoCompressed `
        -Length 3200 `
        -Marker 1
    Assert-Rejection `
        -Fixture $nondeterministic `
        -Operation {
            Invoke-Transaction `
                -Fixture $nondeterministic `
                -VerifyCandidate {
                    param([string]$Directory)
                    & $releaseAssertion -ReleaseDirectory $Directory
                } `
                -BuildSecondRound {
                    [pscustomobject]@{
                        Compressed = $nondeterministic.RoundTwoCompressed
                        Uncompressed = $nondeterministic.RoundTwoUncompressed
                    }
                }
        } `
        -Expected "$recommendedName second publish differs from the verified candidate" `
        -Name "nondeterministic second round"

    $promotionFailure = New-TransactionFixture -Name "promotion-failure"
    $moveCount = 0
    $moveOperation = {
        param([string]$Source, [string]$Destination)

        $script:moveCount++
        if ($script:moveCount -eq 2) {
            throw "synthetic promotion failure"
        }
        Move-Item -LiteralPath $Source -Destination $Destination
    }
    Assert-Rejection `
        -Fixture $promotionFailure `
        -Operation {
            Invoke-Transaction `
                -Fixture $promotionFailure `
                -VerifyCandidate {
                    param([string]$Directory)
                    & $releaseAssertion -ReleaseDirectory $Directory
                } `
                -BuildSecondRound {
                    [pscustomobject]@{
                        Compressed = $promotionFailure.RoundTwoCompressed
                        Uncompressed = $promotionFailure.RoundTwoUncompressed
                    }
                } `
                -MoveDirectory $moveOperation
        } `
        -Expected "release promotion failed: synthetic promotion failure" `
        -Name "promotion restore"
    if ($moveCount -ne 3) {
        throw "promotion failure did not restore the old release through a third move"
    }

    $success = New-TransactionFixture -Name "success"
    $result = Invoke-Transaction `
        -Fixture $success `
        -VerifyCandidate {
            param([string]$Directory)
            & $releaseAssertion -ReleaseDirectory $Directory
        } `
        -BuildSecondRound {
            [pscustomobject]@{
                Compressed = $success.RoundTwoCompressed
                Uncompressed = $success.RoundTwoUncompressed
            }
        }
    if ([IO.Path]::GetFullPath([string]$result) -cne $success.Release) {
        throw "successful transaction returned an unexpected release directory"
    }
    $null = & $releaseAssertion -ReleaseDirectory $success.Release
    $successEntries = @(Get-ChildItem -LiteralPath $success.Release -Force)
    if ($successEntries.Count -ne 2 `
        -or $successEntries.Name -cnotcontains $recommendedName `
        -or $successEntries.Name -cnotcontains $fallbackName) {
        throw "successful transaction did not produce the exact release shape"
    }
    Assert-NoTransactionResidue -Fixture $success
    $passedControls++
}
finally {
    Remove-Module WindowsReleaseTransaction -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}

Write-Output "release transaction regressions passed ($passedControls controls)"
