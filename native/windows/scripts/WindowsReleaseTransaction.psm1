Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:RecommendedName = "ScreenFix-Windows-x64.exe"
$script:FallbackName = "ScreenFix-Windows-x64-uncompressed.exe"
$script:PathComparison = if ($IsWindows) {
    [StringComparison]::OrdinalIgnoreCase
}
else {
    [StringComparison]::Ordinal
}

function Test-PathBeneath {
    param(
        [string]$Parent,
        [string]$Child
    )

    $relative = [IO.Path]::GetRelativePath($Parent, $Child)
    if ($relative -ceq "." -or [IO.Path]::IsPathFullyQualified($relative)) {
        return $false
    }
    if ($relative -ceq "..") {
        return $false
    }

    $parentPrefix = ".." + [IO.Path]::DirectorySeparatorChar
    $alternatePrefix = ".." + [IO.Path]::AltDirectorySeparatorChar
    return -not $relative.StartsWith($parentPrefix, $script:PathComparison) `
        -and -not $relative.StartsWith($alternatePrefix, $script:PathComparison)
}

function Test-ReparseAncestor {
    param(
        [string]$Path,
        [string]$Boundary
    )

    $current = [IO.Path]::GetFullPath($Path)
    while ($true) {
        $item = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
        if ($null -ne $item `
            -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            return $true
        }
        if ($current.Equals($Boundary, $script:PathComparison)) {
            return $false
        }

        $parent = [IO.Path]::GetDirectoryName($current)
        if ([string]::IsNullOrWhiteSpace($parent) `
            -or $parent.Equals($current, $script:PathComparison)) {
            return $true
        }
        $current = $parent
    }
}

function Resolve-ArtifactsParent {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) `
        -or -not [IO.Path]::IsPathFullyQualified($Path)) {
        throw "artifacts parent must be one absolute regular non-reparse directory"
    }

    $normalized = [IO.Path]::GetFullPath($Path)
    $item = Get-Item -LiteralPath $normalized -Force -ErrorAction SilentlyContinue
    $root = [IO.Path]::GetPathRoot($normalized)
    if ($null -eq $item `
        -or $item -isnot [IO.DirectoryInfo] `
        -or (Test-ReparseAncestor -Path $normalized -Boundary $root)) {
        throw "artifacts parent must be one absolute regular non-reparse directory"
    }

    return $normalized
}

function Resolve-ReleaseDirectory {
    param(
        [string]$Path,
        [string]$ArtifactsParent
    )

    if ([string]::IsNullOrWhiteSpace($Path) `
        -or -not [IO.Path]::IsPathFullyQualified($Path)) {
        throw "release directory must be the fixed artifacts release directory"
    }

    $normalized = [IO.Path]::GetFullPath($Path)
    $expected = [IO.Path]::GetFullPath((Join-Path $ArtifactsParent "release"))
    if (-not $normalized.Equals($expected, $script:PathComparison) `
        -or (Test-ReparseAncestor -Path $normalized -Boundary $ArtifactsParent)) {
        throw "release directory must be the fixed artifacts release directory"
    }

    $item = Get-Item -LiteralPath $normalized -Force -ErrorAction SilentlyContinue
    if ($null -ne $item -and $item -isnot [IO.DirectoryInfo]) {
        throw "release directory must be the fixed artifacts release directory"
    }

    return $normalized
}

function Resolve-SourceFile {
    param(
        [string]$Path,
        [string]$ArtifactsParent,
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Path) `
        -or -not [IO.Path]::IsPathFullyQualified($Path)) {
        throw "$Name source must be one absolute regular non-reparse nonempty file"
    }

    $normalized = [IO.Path]::GetFullPath($Path)
    $item = Get-Item -LiteralPath $normalized -Force -ErrorAction SilentlyContinue
    if (-not (Test-PathBeneath -Parent $ArtifactsParent -Child $normalized) `
        -or $null -eq $item `
        -or $item -isnot [IO.FileInfo] `
        -or $item.Length -le 0 `
        -or (Test-ReparseAncestor -Path $normalized -Boundary $ArtifactsParent)) {
        throw "$Name source must be one absolute regular non-reparse nonempty file"
    }

    return $normalized
}

function New-OwnedDirectoryPath {
    param(
        [string]$ArtifactsParent,
        [ValidateSet("candidate", "backup")]
        [string]$Kind
    )

    $path = [IO.Path]::GetFullPath((Join-Path $ArtifactsParent (
        "release.$Kind." + [Guid]::NewGuid().ToString("N"))))
    if (-not (Test-PathBeneath -Parent $ArtifactsParent -Child $path) `
        -or (Test-Path -LiteralPath $path)) {
        throw "owned release $Kind path must be initially absent beneath artifacts"
    }

    return $path
}

function Remove-OwnedDirectory {
    param(
        [string]$Path,
        [string]$ArtifactsParent,
        [ValidateSet("candidate", "backup")]
        [string]$Kind
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    $expectedPrefix = "release.$Kind."
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if (-not (Test-PathBeneath -Parent $ArtifactsParent -Child $Path) `
        -or -not $item.Name.StartsWith($expectedPrefix, [StringComparison]::Ordinal) `
        -or $item -isnot [IO.DirectoryInfo] `
        -or (Test-ReparseAncestor -Path $Path -Boundary $ArtifactsParent)) {
        throw "refusing to remove invalid owned release $Kind directory: $Path"
    }

    Remove-Item -LiteralPath $Path -Recurse -Force
}

function Test-FileBytesEqual {
    param(
        [string]$First,
        [string]$Second
    )

    $firstStream = [IO.File]::OpenRead($First)
    try {
        $secondStream = [IO.File]::OpenRead($Second)
        try {
            if ($firstStream.Length -ne $secondStream.Length) {
                return $false
            }

            $firstBuffer = [byte[]]::new(1024 * 1024)
            $secondBuffer = [byte[]]::new($firstBuffer.Length)
            while ($true) {
                $firstRead = $firstStream.Read($firstBuffer, 0, $firstBuffer.Length)
                $secondRead = $secondStream.Read($secondBuffer, 0, $secondBuffer.Length)
                if ($firstRead -ne $secondRead) {
                    return $false
                }
                if ($firstRead -eq 0) {
                    return $true
                }
                if (-not [Collections.StructuralComparisons]::StructuralEqualityComparer.Equals(
                        $firstBuffer,
                        $secondBuffer)) {
                    return $false
                }
            }
        }
        finally {
            $secondStream.Dispose()
        }
    }
    finally {
        $firstStream.Dispose()
    }
}

function Assert-DeterministicFile {
    param(
        [string]$SecondRound,
        [string]$Candidate,
        [string]$Name
    )

    $secondHash = (Get-FileHash -LiteralPath $SecondRound -Algorithm SHA256).Hash
    $candidateHash = (Get-FileHash -LiteralPath $Candidate -Algorithm SHA256).Hash
    if ($secondHash -cne $candidateHash `
        -or -not (Test-FileBytesEqual -First $SecondRound -Second $Candidate)) {
        throw "$Name second publish differs from the verified candidate"
    }

    Write-Host "$Name deterministic sha256=$secondHash"
}

function Invoke-ReleasePromotion {
    param(
        [string]$Candidate,
        [string]$Release,
        [string]$ArtifactsParent,
        [scriptblock]$MoveDirectory
    )

    $backup = New-OwnedDirectoryPath `
        -ArtifactsParent $ArtifactsParent `
        -Kind "backup"
    $oldMoved = $false
    try {
        if (Test-Path -LiteralPath $Release) {
            if (Test-ReparseAncestor -Path $Release -Boundary $ArtifactsParent) {
                throw "release directory became a reparse point before promotion"
            }
            $null = & $MoveDirectory $Release $backup
            $oldMoved = $true
        }

        if (Test-ReparseAncestor -Path $Candidate -Boundary $ArtifactsParent) {
            throw "candidate directory became a reparse point before promotion"
        }
        $null = & $MoveDirectory $Candidate $Release
    }
    catch {
        $promotionDiagnostic = $_.Exception.Message
        if ($oldMoved) {
            if (Test-Path -LiteralPath $Release) {
                throw (
                    "release promotion failed and automatic restore is unsafe; " +
                    "release=$Release backup=$backup error=$promotionDiagnostic")
            }

            try {
                $null = & $MoveDirectory $backup $Release
                $oldMoved = $false
            }
            catch {
                throw (
                    "release promotion and restore failed; " +
                    "release=$Release backup=$backup error=$promotionDiagnostic " +
                    "restore=$($_.Exception.Message)")
            }
        }

        throw "release promotion failed: $promotionDiagnostic"
    }

    if ($oldMoved) {
        Remove-OwnedDirectory `
            -Path $backup `
            -ArtifactsParent $ArtifactsParent `
            -Kind "backup"
    }
}

function Invoke-WindowsReleaseTransaction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ArtifactsParent,
        [Parameter(Mandatory = $true)]
        [string]$ReleaseDirectory,
        [Parameter(Mandatory = $true)]
        [string]$CompressedSource,
        [Parameter(Mandatory = $true)]
        [string]$UncompressedSource,
        [Parameter(Mandatory = $true)]
        [scriptblock]$VerifyCandidate,
        [Parameter(Mandatory = $true)]
        [scriptblock]$BuildSecondRound,
        [scriptblock]$CopyFile = {
            param([string]$Source, [string]$Destination)
            Copy-Item -LiteralPath $Source -Destination $Destination
        },
        [scriptblock]$MoveDirectory = {
            param([string]$Source, [string]$Destination)
            Move-Item -LiteralPath $Source -Destination $Destination
        }
    )

    $ArtifactsParent = Resolve-ArtifactsParent -Path $ArtifactsParent
    $ReleaseDirectory = Resolve-ReleaseDirectory `
        -Path $ReleaseDirectory `
        -ArtifactsParent $ArtifactsParent
    $CompressedSource = Resolve-SourceFile `
        -Path $CompressedSource `
        -ArtifactsParent $ArtifactsParent `
        -Name "compressed"
    $UncompressedSource = Resolve-SourceFile `
        -Path $UncompressedSource `
        -ArtifactsParent $ArtifactsParent `
        -Name "uncompressed"

    $candidate = New-OwnedDirectoryPath `
        -ArtifactsParent $ArtifactsParent `
        -Kind "candidate"
    try {
        [void](New-Item -ItemType Directory -Path $candidate)
        $candidateCompressed = Join-Path $candidate $script:RecommendedName
        $candidateUncompressed = Join-Path $candidate $script:FallbackName
        $null = & $CopyFile $CompressedSource $candidateCompressed
        $null = & $CopyFile $UncompressedSource $candidateUncompressed

        $null = Resolve-SourceFile `
            -Path $candidateCompressed `
            -ArtifactsParent $ArtifactsParent `
            -Name "candidate compressed"
        $null = Resolve-SourceFile `
            -Path $candidateUncompressed `
            -ArtifactsParent $ArtifactsParent `
            -Name "candidate uncompressed"
        $null = & $VerifyCandidate $candidate

        $secondRoundOutput = @(& $BuildSecondRound)
        if ($secondRoundOutput.Count -ne 1 `
            -or $null -eq $secondRoundOutput[0].Compressed `
            -or $null -eq $secondRoundOutput[0].Uncompressed) {
            throw "second publish did not return exactly one compressed/uncompressed result"
        }
        $secondCompressed = Resolve-SourceFile `
            -Path ([string]$secondRoundOutput[0].Compressed) `
            -ArtifactsParent $ArtifactsParent `
            -Name "second compressed"
        $secondUncompressed = Resolve-SourceFile `
            -Path ([string]$secondRoundOutput[0].Uncompressed) `
            -ArtifactsParent $ArtifactsParent `
            -Name "second uncompressed"
        Assert-DeterministicFile `
            -SecondRound $secondCompressed `
            -Candidate $candidateCompressed `
            -Name $script:RecommendedName
        Assert-DeterministicFile `
            -SecondRound $secondUncompressed `
            -Candidate $candidateUncompressed `
            -Name $script:FallbackName

        Invoke-ReleasePromotion `
            -Candidate $candidate `
            -Release $ReleaseDirectory `
            -ArtifactsParent $ArtifactsParent `
            -MoveDirectory $MoveDirectory
        return $ReleaseDirectory
    }
    finally {
        Remove-OwnedDirectory `
            -Path $candidate `
            -ArtifactsParent $ArtifactsParent `
            -Kind "candidate"
    }
}

Export-ModuleMember -Function Invoke-WindowsReleaseTransaction
