param(
    [Parameter(Mandatory = $true)]
    [string]$DotnetPath,
    [Parameter(Mandatory = $true)]
    [string]$ExternalDotnetPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-DotnetLauncher {
    param(
        [string]$Path,
        [string]$Name
    )

    $diagnostic = (
        "$Name dotnet path must be one absolute regular non-reparse executable file")
    if ([string]::IsNullOrWhiteSpace($Path) `
        -or -not [IO.Path]::IsPathFullyQualified($Path)) {
        throw $diagnostic
    }

    $normalized = [IO.Path]::GetFullPath($Path)
    $item = Get-Item -LiteralPath $normalized -Force -ErrorAction SilentlyContinue
    if ($null -eq $item `
        -or $item -isnot [IO.FileInfo] `
        -or $item.Length -le 0 `
        -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw $diagnostic
    }

    if ($IsWindows) {
        if (@(".exe", ".com", ".cmd", ".bat", ".ps1") -cnotcontains `
            $item.Extension.ToLowerInvariant()) {
            throw $diagnostic
        }
    }
    else {
        $executeMask = [int]([IO.UnixFileMode]::UserExecute -bor `
            [IO.UnixFileMode]::GroupExecute -bor `
            [IO.UnixFileMode]::OtherExecute)
        $mode = [int][IO.File]::GetUnixFileMode($normalized)
        if (($mode -band $executeMask) -eq 0) {
            throw $diagnostic
        }
    }

    return $normalized
}

$DotnetPath = Resolve-DotnetLauncher -Path $DotnetPath -Name "private"
$ExternalDotnetPath = Resolve-DotnetLauncher `
    -Path $ExternalDotnetPath `
    -Name "external"

$assertion = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "assert-win-x64-package.ps1"))
$toolchainAssertion = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "assert-pinned-win-x64-toolchain.ps1"))
$canonicalIcon = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "../src/ScreenFix.App/Resources/ScreenFix.ico"))
$appProject = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "../src/ScreenFix.App/ScreenFix.App.csproj"))
$verifierProject = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "../tools/ScreenFix.PackageVerifier/ScreenFix.PackageVerifier.csproj"))
$verifierAssembly = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "../tools/ScreenFix.PackageVerifier/bin/Release/net10.0/ScreenFix.PackageVerifier.dll"))
$windowsTestProject = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "../tests/ScreenFix.Windows.Tests/ScreenFix.Windows.Tests.csproj"))
$publishScript = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "publish-win-x64.ps1"))
$regressionScriptSource = [IO.File]::ReadAllText($MyInvocation.MyCommand.Path)
$ambientDotnetResolver = "Get-Command " + "dotnet"
if ($regressionScriptSource.Contains($ambientDotnetResolver)) {
    throw "package regressions must require an absolute dotnet launcher"
}

$toolchainCallMarker = "& " + '$toolchainAssertion'
$externalArgumentMarker = "-ExternalDotnetPath " + '$ExternalDotnetPath'
$baselineArgumentMarker = "-BaselineAssetsPath " + '$realAssets["uncompressed"]'
$candidateArgumentMarker = "-CandidateAssetsPath " + '$realAssets["compressed"]'
if (-not $regressionScriptSource.Contains($toolchainCallMarker) `
    -or -not $regressionScriptSource.Contains($externalArgumentMarker) `
    -or -not $regressionScriptSource.Contains($baselineArgumentMarker) `
    -or -not $regressionScriptSource.Contains($candidateArgumentMarker)) {
    throw "package regressions must assert both isolated runtime-pack assets"
}

$publishScriptSource = [IO.File]::ReadAllText($publishScript)
if ($publishScriptSource.Contains($ambientDotnetResolver) `
    -or $publishScriptSource -notmatch `
        '(?s)\[Parameter\(Mandatory\s*=\s*\$true\)\]\s*\[string\]\$DotnetPath') {
    throw "publish script must require an absolute dotnet launcher"
}

if (-not $publishScriptSource.Contains('& $dotnetPath publish')) {
    throw "publish script must use its resolved absolute dotnet launcher"
}

if (-not $publishScriptSource.Contains('-DotnetPath $dotnetPath') `
    -or -not $publishScriptSource.Contains('-ExpectedCompression uncompressed')) {
    throw "publish script must declare its package mode to Windows native tests"
}

$temporaryRoot = Join-Path (
    [IO.Path]::GetTempPath()) (
    "ScreenFix.PackageTests." + [Guid]::NewGuid().ToString("N"))

function Invoke-CheckedDotnet {
    param(
        [string[]]$Arguments,
        [string]$Failure
    )

    & $DotnetPath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Failure with exit code $LASTEXITCODE"
    }
}

function Invoke-ScreenFixPublish {
    param(
        [ValidateSet("compressed", "uncompressed")]
        [string]$Mode,
        [string]$ArtifactsPath,
        [string]$OutputPath,
        [string]$ManagedIcon,
        [switch]$WithoutNativeIcon
    )

    $compression = if ($Mode -ceq "compressed") { "true" } else { "false" }
    $arguments = @(
        "publish",
        $appProject,
        "-c", "Release",
        "-r", "win-x64",
        "--self-contained", "true",
        "--artifacts-path", $ArtifactsPath,
        "-p:PublishSingleFile=true",
        "-p:IncludeNativeLibrariesForSelfExtract=true",
        "-p:EnableCompressionInSingleFile=$compression",
        "-p:PublishTrimmed=false",
        "-p:UseAppHost=true",
        "-p:DebugType=None",
        "-p:DebugSymbols=false",
        "-o", $OutputPath)

    if (-not [string]::IsNullOrWhiteSpace($ManagedIcon)) {
        $arguments += "-p:ScreenFixManagedIcon=$ManagedIcon"
    }

    if ($WithoutNativeIcon) {
        $arguments += "-p:ApplicationIcon="
    }

    Invoke-CheckedDotnet -Arguments $arguments -Failure "$Mode publish failed"
    & $assertion -OutputDirectory $OutputPath
}

function Resolve-AppAssetsPath {
    param(
        [string]$ArtifactsPath,
        [ValidateSet("compressed", "uncompressed")]
        [string]$Mode
    )

    $matches = @(Get-ChildItem `
        -LiteralPath $ArtifactsPath `
        -Recurse `
        -File `
        -Filter "project.assets.json" | Where-Object {
            $relative = [IO.Path]::GetRelativePath($ArtifactsPath, $_.FullName)
            $relative -match '^obj[\\/]ScreenFix\.App[\\/]project\.assets\.json$'
        })
    if ($matches.Count -ne 1) {
        throw "$Mode artifacts must contain exactly one ScreenFix.App project.assets.json; found $($matches.Count)"
    }

    return [IO.Path]::GetFullPath($matches[0].FullName)
}

function Invoke-PackageVerifier {
    param(
        [string]$Executable,
        [ValidateSet("compressed", "uncompressed")]
        [string]$Mode
    )

    & $DotnetPath $verifierAssembly `
        --executable $Executable `
        --canonical-icon $canonicalIcon `
        --compression $Mode
    if ($LASTEXITCODE -ne 0) {
        throw "$Mode package verification failed with exit code $LASTEXITCODE"
    }
}

function Get-VerifierRejection {
    param(
        [string]$Executable,
        [ValidateSet("compressed", "uncompressed")]
        [string]$Mode
    )

    $output = & $DotnetPath $verifierAssembly `
        --executable $Executable `
        --canonical-icon $canonicalIcon `
        --compression $Mode 2>&1
    $exitCode = $LASTEXITCODE
    $diagnostic = ($output -join [Environment]::NewLine).Trim()
    if ($exitCode -eq 0) {
        throw "$Mode package verification unexpectedly passed"
    }

    return $diagnostic
}

function Resolve-AppHostCandidateStates {
    param(
        [object[]]$Candidates,
        [StringComparer]$PathComparer
    )

    $seen = [Collections.Generic.HashSet[string]]::new($PathComparer)
    $found = [Collections.Generic.List[string]]::new()
    foreach ($candidate in $Candidates) {
        $normalized = [IO.Path]::GetFullPath([string]$candidate.Path)
        if (-not [bool]$candidate.Exists) {
            continue
        }

        if (-not [bool]$candidate.IsRegular `
            -or [long]$candidate.Length -le 0) {
            throw "shared RID apphost candidate must be one regular nonempty file: $normalized"
        }

        if ($seen.Add($normalized)) {
            [void]$found.Add($normalized)
        }
    }

    if ($found.Count -eq 0) {
        throw "shared RID apphost does not exist in SDK packs or NuGet global packages"
    }

    return $found.ToArray()
}

function Resolve-SharedAppHosts {
    param(
        [string]$DotnetRoot,
        [string]$GlobalPackagesRoot
    )

    $candidates = @(
        (Join-Path $DotnetRoot (
            "packs/Microsoft.NETCore.App.Host.win-x64/10.0.0/runtimes/win-x64/native/apphost.exe")),
        (Join-Path $GlobalPackagesRoot (
            "microsoft.netcore.app.host.win-x64/10.0.0/runtimes/win-x64/native/apphost.exe")))
    $candidateStates = [Collections.Generic.List[object]]::new()
    foreach ($candidate in $candidates) {
        $normalized = [IO.Path]::GetFullPath($candidate)
        $item = Get-Item `
            -LiteralPath $normalized `
            -Force `
            -ErrorAction SilentlyContinue
        if ($null -eq $item) {
            [void]$candidateStates.Add([pscustomobject]@{
                Path = $normalized
                Exists = $false
                IsRegular = $false
                Length = 0
            })
        }
        else {
            [void]$candidateStates.Add([pscustomobject]@{
                Path = $normalized
                Exists = $true
                IsRegular = -not $item.PSIsContainer -and -not (
                    $item.Attributes -band [IO.FileAttributes]::ReparsePoint)
                Length = if ($item.PSIsContainer) { 0 } else { $item.Length }
            })
        }
    }

    $pathComparer = if ($IsWindows) {
        [StringComparer]::OrdinalIgnoreCase
    }
    else {
        [StringComparer]::Ordinal
    }

    return Resolve-AppHostCandidateStates `
        -Candidates $candidateStates.ToArray() `
        -PathComparer $pathComparer
}

function Get-SharedAppHostSnapshots {
    param(
        [string[]]$AppHosts,
        [scriptblock]$HashProvider = {
            param([string]$Path)

            (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
        }
    )

    $snapshots = [Collections.Generic.List[object]]::new()
    foreach ($appHost in $AppHosts) {
        [void]$snapshots.Add([pscustomobject]@{
            Path = $appHost
            Hash = & $HashProvider $appHost
        })
    }

    return $snapshots.ToArray()
}

function Assert-SharedAppHostsUnchanged {
    param(
        [object[]]$ExpectedSnapshots,
        [scriptblock]$HashProvider = {
            param([string]$Path)

            (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
        }
    )

    foreach ($snapshot in $ExpectedSnapshots) {
        $actualHash = & $HashProvider ([string]$snapshot.Path)
        if ($actualHash -cne [string]$snapshot.Hash) {
            throw "shared RID apphost changed during an isolated publish: $($snapshot.Path)"
        }
    }
}

$previousExecutable = $env:SCREENFIX_PUBLISHED_EXE
$previousCanonical = $env:SCREENFIX_CANONICAL_ICO
try {
    [void](New-Item -ItemType Directory -Path $temporaryRoot)
    $sdkAppHostSuffix = "packs/Microsoft.NETCore.App.Host.win-x64/10.0.0/runtimes/win-x64/native/apphost.exe"
    $nugetAppHostSuffix = "microsoft.netcore.app.host.win-x64/10.0.0/runtimes/win-x64/native/apphost.exe"
    $resolutionRoot = Join-Path $temporaryRoot "apphost-resolution"
    $upperCaseCandidate = Join-Path $resolutionRoot "case/Microsoft.NETCore.App.Host.win-x64/apphost.exe"
    $lowerCaseCandidate = Join-Path $resolutionRoot "case/microsoft.netcore.app.host.win-x64/apphost.exe"

    $caseDistinctResult = @(Resolve-AppHostCandidateStates `
        -Candidates @(
            [pscustomobject]@{
                Path = $upperCaseCandidate
                Exists = $true
                IsRegular = $true
                Length = 3
            },
            [pscustomobject]@{
                Path = $lowerCaseCandidate
                Exists = $true
                IsRegular = $true
                Length = 3
            }) `
        -PathComparer ([StringComparer]::Ordinal))
    if ($caseDistinctResult.Count -ne 2) {
        throw "case-distinct apphost candidates must remain distinct off Windows"
    }

    $caseEquivalentResult = @(Resolve-AppHostCandidateStates `
        -Candidates @(
            [pscustomobject]@{
                Path = $upperCaseCandidate
                Exists = $true
                IsRegular = $true
                Length = 3
            },
            [pscustomobject]@{
                Path = $lowerCaseCandidate
                Exists = $true
                IsRegular = $true
                Length = 3
            }) `
        -PathComparer ([StringComparer]::OrdinalIgnoreCase))
    if ($caseEquivalentResult.Count -ne 1) {
        throw "case-equivalent Windows apphost candidates were not deduplicated"
    }

    $invalidCaseDiagnostic = $null
    try {
        [void](Resolve-AppHostCandidateStates `
            -Candidates @(
                [pscustomobject]@{
                    Path = $upperCaseCandidate
                    Exists = $true
                    IsRegular = $true
                    Length = 3
                },
                [pscustomobject]@{
                    Path = $lowerCaseCandidate
                    Exists = $true
                    IsRegular = $true
                    Length = 0
                }) `
            -PathComparer ([StringComparer]::OrdinalIgnoreCase))
    }
    catch {
        $invalidCaseDiagnostic = $_.Exception.Message
    }
    if (-not $invalidCaseDiagnostic.StartsWith(
            "shared RID apphost candidate must be one regular nonempty file:")) {
        throw "case-equivalent invalid apphost candidate was hidden by deduplication"
    }

    $secondOnlyResult = @(Resolve-AppHostCandidateStates `
        -Candidates @(
            [pscustomobject]@{
                Path = $upperCaseCandidate
                Exists = $false
                IsRegular = $false
                Length = 0
            },
            [pscustomobject]@{
                Path = $lowerCaseCandidate
                Exists = $true
                IsRegular = $true
                Length = 3
            }) `
        -PathComparer ([StringComparer]::OrdinalIgnoreCase))
    if ($secondOnlyResult.Count -ne 1 `
        -or $secondOnlyResult[0] -cne [IO.Path]::GetFullPath($lowerCaseCandidate)) {
        throw "case-equivalent missing candidate hid the valid second apphost"
    }

    $baselineHashProvider = {
        param([string]$Path)

        if ($Path -ceq [IO.Path]::GetFullPath($upperCaseCandidate)) {
            return "upper-hash"
        }

        if ($Path -ceq [IO.Path]::GetFullPath($lowerCaseCandidate)) {
            return "lower-hash"
        }

        throw "unexpected synthetic apphost path: $Path"
    }
    $caseDistinctSnapshots = @(Get-SharedAppHostSnapshots `
        -AppHosts $caseDistinctResult `
        -HashProvider $baselineHashProvider)
    if ($caseDistinctSnapshots.Count -ne 2) {
        throw "case-distinct apphost snapshots collided"
    }

    Assert-SharedAppHostsUnchanged `
        -ExpectedSnapshots $caseDistinctSnapshots `
        -HashProvider $baselineHashProvider

    foreach ($mutatedPath in @($upperCaseCandidate, $lowerCaseCandidate)) {
        $mutationHashProvider = {
            param([string]$Path)

            if ($Path -ceq [IO.Path]::GetFullPath($mutatedPath)) {
                return "mutated-hash"
            }

            & $baselineHashProvider $Path
        }
        $mutationDiagnostic = $null
        try {
            Assert-SharedAppHostsUnchanged `
                -ExpectedSnapshots $caseDistinctSnapshots `
                -HashProvider $mutationHashProvider
        }
        catch {
            $mutationDiagnostic = $_.Exception.Message
        }
        $expectedMutationDiagnostic = (
            "shared RID apphost changed during an isolated publish: " +
            [IO.Path]::GetFullPath($mutatedPath))
        if ($mutationDiagnostic -cne $expectedMutationDiagnostic) {
            throw "case-distinct apphost mutation was not detected: $mutationDiagnostic"
        }
    }

    $sdkOnlyRoot = Join-Path $resolutionRoot "sdk-only/dotnet"
    $sdkOnlyAppHost = Join-Path $sdkOnlyRoot $sdkAppHostSuffix
    [void](New-Item -ItemType Directory -Force -Path (Split-Path $sdkOnlyAppHost))
    [IO.File]::WriteAllBytes($sdkOnlyAppHost, [byte[]](1, 2, 3))
    $sdkOnlyResult = @(Resolve-SharedAppHosts `
        -DotnetRoot $sdkOnlyRoot `
        -GlobalPackagesRoot (Join-Path $resolutionRoot "sdk-only/nuget"))
    if ($sdkOnlyResult.Count -ne 1 `
        -or $sdkOnlyResult[0] -cne [IO.Path]::GetFullPath($sdkOnlyAppHost)) {
        throw "SDK-pack-only apphost resolution returned an unexpected result"
    }

    $nugetOnlyRoot = Join-Path $resolutionRoot "nuget-only/packages"
    $nugetOnlyAppHost = Join-Path $nugetOnlyRoot $nugetAppHostSuffix
    [void](New-Item -ItemType Directory -Force -Path (Split-Path $nugetOnlyAppHost))
    [IO.File]::WriteAllBytes($nugetOnlyAppHost, [byte[]](4, 5, 6))
    $nugetOnlyResult = @(Resolve-SharedAppHosts `
        -DotnetRoot (Join-Path $resolutionRoot "nuget-only/dotnet") `
        -GlobalPackagesRoot $nugetOnlyRoot)
    if ($nugetOnlyResult.Count -ne 1 `
        -or $nugetOnlyResult[0] -cne [IO.Path]::GetFullPath($nugetOnlyAppHost)) {
        throw "NuGet-only apphost resolution returned an unexpected result"
    }

    $bothDotnetRoot = Join-Path $resolutionRoot "both/dotnet"
    $bothNugetRoot = Join-Path $resolutionRoot "both/packages"
    $bothSdkAppHost = Join-Path $bothDotnetRoot $sdkAppHostSuffix
    $bothNugetAppHost = Join-Path $bothNugetRoot $nugetAppHostSuffix
    [void](New-Item -ItemType Directory -Force -Path (Split-Path $bothSdkAppHost))
    [void](New-Item -ItemType Directory -Force -Path (Split-Path $bothNugetAppHost))
    [IO.File]::WriteAllBytes($bothSdkAppHost, [byte[]](7, 8, 9))
    [IO.File]::WriteAllBytes($bothNugetAppHost, [byte[]](10, 11, 12))
    $bothResult = @(Resolve-SharedAppHosts `
        -DotnetRoot $bothDotnetRoot `
        -GlobalPackagesRoot $bothNugetRoot)
    if ($bothResult.Count -ne 2 `
        -or $bothResult -cnotcontains [IO.Path]::GetFullPath($bothSdkAppHost) `
        -or $bothResult -cnotcontains [IO.Path]::GetFullPath($bothNugetAppHost)) {
        throw "combined apphost resolution returned an unexpected result"
    }

    $missingDiagnostic = $null
    try {
        [void](Resolve-SharedAppHosts `
            -DotnetRoot (Join-Path $resolutionRoot "missing/dotnet") `
            -GlobalPackagesRoot (Join-Path $resolutionRoot "missing/packages"))
    }
    catch {
        $missingDiagnostic = $_.Exception.Message
    }
    if ($missingDiagnostic -cne (
            "shared RID apphost does not exist in SDK packs or NuGet global packages")) {
        throw "unexpected missing-apphost rejection: $missingDiagnostic"
    }

    $invalidDotnetRoot = Join-Path $resolutionRoot "invalid/dotnet"
    $invalidNugetRoot = Join-Path $resolutionRoot "invalid/packages"
    $validSdkAppHost = Join-Path $invalidDotnetRoot $sdkAppHostSuffix
    $emptyNugetAppHost = Join-Path $invalidNugetRoot $nugetAppHostSuffix
    [void](New-Item -ItemType Directory -Force -Path (Split-Path $validSdkAppHost))
    [void](New-Item -ItemType Directory -Force -Path (Split-Path $emptyNugetAppHost))
    [IO.File]::WriteAllBytes($validSdkAppHost, [byte[]](16, 17, 18))
    [IO.File]::WriteAllBytes($emptyNugetAppHost, [byte[]]::new(0))
    $invalidDiagnostic = $null
    try {
        [void](Resolve-SharedAppHosts `
            -DotnetRoot $invalidDotnetRoot `
            -GlobalPackagesRoot $invalidNugetRoot)
    }
    catch {
        $invalidDiagnostic = $_.Exception.Message
    }
    if (-not $invalidDiagnostic.StartsWith(
            "shared RID apphost candidate must be one regular nonempty file:")) {
        throw "unexpected invalid-apphost rejection: $invalidDiagnostic"
    }

    $structuralDirectory = Join-Path $temporaryRoot "structural"
    [void](New-Item -ItemType Directory -Path $structuralDirectory)
    $structuralExecutable = Join-Path $structuralDirectory "ScreenFix.exe"

    $bytes = [byte[]]::new(256)
    $bytes[0] = 0x4d
    $bytes[1] = 0x5a
    $bytes[0x3c] = 0x80
    $bytes[0x84] = 0x64
    $bytes[0x85] = 0x86
    [IO.File]::WriteAllBytes($structuralExecutable, $bytes)

    $rejection = $null
    try {
        & $assertion -OutputDirectory $structuralDirectory
    }
    catch {
        $rejection = $_.Exception.Message
    }

    if ($rejection -cne "executable does not have a PE signature") {
        throw "unexpected rejection: $rejection"
    }

    $bytes[0x80] = 0x50
    $bytes[0x81] = 0x45
    $bytes[0x82] = 0
    $bytes[0x83] = 0
    $bytes[0x94] = 0x68
    [IO.File]::WriteAllBytes($structuralExecutable, $bytes)
    $rejection = $null
    try {
        & $assertion -OutputDirectory $structuralDirectory
    }
    catch {
        $rejection = $_.Exception.Message
    }

    if ($rejection -cne "executable optional header is not PE32+: 0x0000") {
        throw "unexpected rejection: $rejection"
    }

    $bytes[0x98] = 0x0b
    $bytes[0x99] = 0x02
    $bytes[0xdc] = 0x03
    $bytes[0xdd] = 0
    [IO.File]::WriteAllBytes($structuralExecutable, $bytes)
    $rejection = $null
    try {
        & $assertion -OutputDirectory $structuralDirectory
    }
    catch {
        $rejection = $_.Exception.Message
    }

    if ($rejection -cne "executable subsystem is not Windows GUI: 3") {
        throw "unexpected rejection: $rejection"
    }

    $bytes[0xdc] = 0x02
    [IO.File]::WriteAllBytes($structuralExecutable, $bytes)
    & $assertion -OutputDirectory $structuralDirectory

    $bytes[0x84] = 0x4c
    $bytes[0x85] = 0x01
    [IO.File]::WriteAllBytes($structuralExecutable, $bytes)
    $rejection = $null
    try {
        & $assertion -OutputDirectory $structuralDirectory
    }
    catch {
        $rejection = $_.Exception.Message
    }

    if ($rejection -cne "executable machine is not AMD64: 0x014c") {
        throw "unexpected wrong-machine rejection: $rejection"
    }

    [IO.File]::WriteAllText(
        (Join-Path $structuralDirectory "companion.txt"),
        "unexpected")
    $rejection = $null
    try {
        & $assertion -OutputDirectory $structuralDirectory
    }
    catch {
        $rejection = $_.Exception.Message
    }

    if ($rejection -cne "package must contain exactly one regular file; found 2") {
        throw "unexpected companion-file rejection: $rejection"
    }

    Remove-Item -LiteralPath (Join-Path $structuralDirectory "companion.txt")
    [IO.File]::WriteAllBytes($structuralExecutable, [byte[]]::new(0))
    $rejection = $null
    try {
        & $assertion -OutputDirectory $structuralDirectory
    }
    catch {
        $rejection = $_.Exception.Message
    }

    if ($rejection -cne "executable is empty") {
        throw "unexpected empty-file rejection: $rejection"
    }

    Invoke-CheckedDotnet `
        -Arguments @("build", $verifierProject, "-c", "Release") `
        -Failure "package verifier build failed"

    $realPackages = @{}
    $realAssets = @{}
    foreach ($mode in @("uncompressed", "compressed")) {
        $artifactsPath = Join-Path $temporaryRoot "real-$mode-artifacts"
        $outputPath = Join-Path $temporaryRoot "real-$mode-publish"
        Invoke-ScreenFixPublish `
            -Mode $mode `
            -ArtifactsPath $artifactsPath `
            -OutputPath $outputPath
        $executable = Join-Path $outputPath "ScreenFix.exe"
        Invoke-PackageVerifier -Executable $executable -Mode $mode
        $realPackages[$mode] = $executable
        $realAssets[$mode] = Resolve-AppAssetsPath `
            -ArtifactsPath $artifactsPath `
            -Mode $mode

        $wrongMode = if ($mode -ceq "compressed") { "uncompressed" } else { "compressed" }
        $wrongModeDiagnostic = Get-VerifierRejection `
            -Executable $executable `
            -Mode $wrongMode
        $expectedDiagnostic = if ($mode -ceq "compressed") {
            "expected uncompressed ScreenFix.dll but CompressedSize is positive"
        }
        else {
            "expected compressed ScreenFix.dll but CompressedSize is zero"
        }
        if ($wrongModeDiagnostic -cne $expectedDiagnostic) {
            throw "unexpected wrong-mode rejection: $wrongModeDiagnostic"
        }
    }

    & $toolchainAssertion `
        -DotnetPath $DotnetPath `
        -ExternalDotnetPath $ExternalDotnetPath `
        -Project $appProject `
        -BaselineAssetsPath $realAssets["uncompressed"] `
        -CandidateAssetsPath $realAssets["compressed"]

    $globalPackagesOutput = & $DotnetPath nuget locals global-packages --list
    if ($LASTEXITCODE -ne 0) {
        throw "global packages path query failed with exit code $LASTEXITCODE"
    }

    $globalPackagesLines = @($globalPackagesOutput | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_)
    })
    if ($globalPackagesLines.Count -ne 1 `
        -or $globalPackagesLines[0] -notmatch "^[^:]+:\s*(.+)$") {
        throw "global packages path query returned an unexpected result"
    }

    $globalPackages = [IO.Path]::GetFullPath($Matches[1])
    $dotnetRoot = Split-Path -Parent $DotnetPath
    $sharedAppHosts = @(Resolve-SharedAppHosts `
        -DotnetRoot $dotnetRoot `
        -GlobalPackagesRoot $globalPackages)
    $sharedAppHostSnapshots = @(
        Get-SharedAppHostSnapshots -AppHosts $sharedAppHosts)

    $mutatedIcon = Join-Path $temporaryRoot "mutated-ScreenFix.ico"
    $mutatedIconBytes = [IO.File]::ReadAllBytes($canonicalIcon)
    $mutatedIconBytes[$mutatedIconBytes.Length - 1] = `
        $mutatedIconBytes[$mutatedIconBytes.Length - 1] -bxor 0xff
    [IO.File]::WriteAllBytes($mutatedIcon, $mutatedIconBytes)
    $mutatedArtifacts = Join-Path $temporaryRoot "mutated-managed-icon-artifacts"
    $mutatedOutput = Join-Path $temporaryRoot "mutated-managed-icon-publish"
    Invoke-ScreenFixPublish `
        -Mode "compressed" `
        -ArtifactsPath $mutatedArtifacts `
        -OutputPath $mutatedOutput `
        -ManagedIcon $mutatedIcon
    $mutatedDiagnostic = Get-VerifierRejection `
        -Executable (Join-Path $mutatedOutput "ScreenFix.exe") `
        -Mode "compressed"
    if ($mutatedDiagnostic -cne "managed icon does not match canonical icon") {
        throw "unexpected mutated managed-icon rejection: $mutatedDiagnostic"
    }
    Assert-SharedAppHostsUnchanged -ExpectedSnapshots $sharedAppHostSnapshots

    if ($IsWindows) {
        Invoke-CheckedDotnet `
            -Arguments @("build", $windowsTestProject, "-c", "Release") `
            -Failure "Windows icon test build failed"
        $env:SCREENFIX_CANONICAL_ICO = $canonicalIcon

        foreach ($mode in @("uncompressed", "compressed")) {
            $env:SCREENFIX_PUBLISHED_EXE = $realPackages[$mode]
            Invoke-CheckedDotnet `
                -Arguments @(
                    "test", $windowsTestProject,
                    "-c", "Release",
                    "--no-build",
                    "--filter", "FullyQualifiedName~PublishedExecutable_ContainsEveryNativeIconFrame") `
                -Failure "$mode real-package native icon test failed"

            $iconlessArtifacts = Join-Path $temporaryRoot "iconless-$mode-artifacts"
            $iconlessOutput = Join-Path $temporaryRoot "iconless-$mode-publish"
            Invoke-ScreenFixPublish `
                -Mode $mode `
                -ArtifactsPath $iconlessArtifacts `
                -OutputPath $iconlessOutput `
                -WithoutNativeIcon
            $iconlessExecutable = Join-Path $iconlessOutput "ScreenFix.exe"
            Invoke-PackageVerifier -Executable $iconlessExecutable -Mode $mode
            Assert-SharedAppHostsUnchanged -ExpectedSnapshots $sharedAppHostSnapshots

            $env:SCREENFIX_PUBLISHED_EXE = $iconlessExecutable
            $nativeIconOutput = & $DotnetPath test $windowsTestProject `
                -c Release `
                --no-build `
                --logger "console;verbosity=normal" `
                --filter "FullyQualifiedName~PublishedExecutable_ContainsEveryNativeIconFrame" 2>&1
            $nativeIconExit = $LASTEXITCODE
            $nativeIconOutput | Write-Output
            if ($nativeIconExit -eq 0) {
                throw "$mode iconless apphost was accepted"
            }

            $nativeIconDiagnostic = [regex]::Replace(
                ($nativeIconOutput -join [Environment]::NewLine),
                "\s+",
                " ")
            if (-not $nativeIconDiagnostic.Contains(
                    "PublishedExecutable_ContainsEveryNativeIconFrame") `
                -or -not $nativeIconDiagnostic.Contains(
                    "does not contain an RT_GROUP_ICON with the exact Screen Patch frame set and payloads")) {
                throw "$mode iconless apphost failed for an unexpected reason"
            }

            $positiveArtifacts = Join-Path $temporaryRoot "post-iconless-$mode-artifacts"
            $positiveOutput = Join-Path $temporaryRoot "post-iconless-$mode-publish"
            Invoke-ScreenFixPublish `
                -Mode $mode `
                -ArtifactsPath $positiveArtifacts `
                -OutputPath $positiveOutput
            $positiveExecutable = Join-Path $positiveOutput "ScreenFix.exe"
            Invoke-PackageVerifier -Executable $positiveExecutable -Mode $mode
            Assert-SharedAppHostsUnchanged -ExpectedSnapshots $sharedAppHostSnapshots

            $env:SCREENFIX_PUBLISHED_EXE = $positiveExecutable
            Invoke-CheckedDotnet `
                -Arguments @(
                    "test", $windowsTestProject,
                    "-c", "Release",
                    "--no-build",
                    "--filter", "FullyQualifiedName~PublishedExecutable_ContainsEveryNativeIconFrame") `
                -Failure "$mode default apphost remained iconless after the negative control"
        }
    }
    else {
        Write-Output "Native PE icon controls require Windows."
    }

    Assert-SharedAppHostsUnchanged -ExpectedSnapshots $sharedAppHostSnapshots
}
finally {
    $env:SCREENFIX_PUBLISHED_EXE = $previousExecutable
    $env:SCREENFIX_CANONICAL_ICO = $previousCanonical
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}

Write-Output "package assertion regression tests passed"
