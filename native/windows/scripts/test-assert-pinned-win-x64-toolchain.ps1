Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$assertion = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "assert-pinned-win-x64-toolchain.ps1"))
$project = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "../src/ScreenFix.App/ScreenFix.App.csproj"))
$temporaryBase = if (-not $IsWindows `
    -and (Test-Path -LiteralPath "/private/tmp" -PathType Container)) {
    "/private/tmp"
}
else {
    [IO.Path]::GetTempPath()
}
$temporaryRoot = Join-Path $temporaryBase (
    "ScreenFix.ToolchainTests." + [Guid]::NewGuid().ToString("N"))
$passedControls = 0

function ConvertTo-SingleQuotedLiteral {
    param([string]$Value)

    return "'" + $Value.Replace("'", "''") + "'"
}

function ConvertTo-ArrayLiteral {
    param([AllowEmptyCollection()][string[]]$Values)

    if ($null -eq $Values -or $Values.Count -eq 0) {
        return "@()"
    }

    $literals = @($Values | ForEach-Object {
        ConvertTo-SingleQuotedLiteral -Value $_
    })
    return "@(" + ($literals -join ", ") + ")"
}

function Set-LauncherExecutable {
    param(
        [string]$Path,
        [bool]$Executable
    )

    if ($IsWindows) {
        return
    }

    $mode = [IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite
    if ($Executable) {
        $mode = $mode -bor [IO.UnixFileMode]::UserExecute
    }

    [IO.File]::SetUnixFileMode($Path, $mode)
}

function New-DirectorySymlink {
    param(
        [string]$Path,
        [string]$Target
    )

    try {
        [void](New-Item `
            -ItemType SymbolicLink `
            -Path $Path `
            -Target $Target `
            -ErrorAction Stop)
        return $true
    }
    catch {
        Write-Warning "symlink ancestor control skipped because symlink creation is unavailable: $($_.Exception.Message)"
        return $false
    }
}

function New-FakeDotnet {
    param(
        [string]$Root,
        [string]$Version,
        [AllowEmptyCollection()][string[]]$SdkLines,
        [string]$MsBuildVersion,
        [string]$MsBuildSdksPath,
        [string]$CapturePath
    )

    [void](New-Item -ItemType Directory -Force -Path $Root)
    $launcher = Join-Path $Root "dotnet.ps1"
    $source = @"
param([Parameter(ValueFromRemainingArguments = `$true)][string[]]`$Remaining)
Add-Content -LiteralPath $(ConvertTo-SingleQuotedLiteral $CapturePath) -Value (`$Remaining -join '|')
if (`$Remaining.Count -eq 1 -and `$Remaining[0] -ceq '--version') {
    Write-Output $(ConvertTo-SingleQuotedLiteral $Version)
    exit 0
}
if (`$Remaining.Count -eq 1 -and `$Remaining[0] -ceq '--list-sdks') {
    $(ConvertTo-ArrayLiteral $SdkLines) | Write-Output
    exit 0
}
if (`$Remaining.Count -eq 1 -and `$Remaining[0] -ceq '--info') {
    Write-Output 'synthetic dotnet info'
    exit 0
}
if (`$Remaining.Count -eq 4 -and `$Remaining[0] -ceq 'msbuild' -and `$Remaining[2] -ceq '-nologo') {
    if (`$Remaining[3] -ceq '-getProperty:NETCoreSdkVersion') {
        Write-Output $(ConvertTo-SingleQuotedLiteral $MsBuildVersion)
        exit 0
    }
    if (`$Remaining[3] -ceq '-getProperty:MSBuildSDKsPath') {
        Write-Output $(ConvertTo-SingleQuotedLiteral $MsBuildSdksPath)
        exit 0
    }
}
Write-Error ('unexpected synthetic dotnet arguments: ' + (`$Remaining -join ' '))
exit 91
"@
    [IO.File]::WriteAllText($launcher, $source)
    Set-LauncherExecutable -Path $launcher -Executable $true
    return [IO.Path]::GetFullPath($launcher)
}

function Write-AssetsFile {
    param(
        [string]$Path,
        [string[]]$RuntimePacks,
        [AllowEmptyCollection()][object[]]$DownloadOnlyDependencies
    )

    $frameworkReferences = [ordered]@{}
    $downloadDependencies = [ordered]@{}
    foreach ($runtimePack in $RuntimePacks) {
        if ($runtimePack -notmatch '^(?<Name>Microsoft\..*\.App\.Runtime\.win-x64)/(?<Version>[^/]+)$') {
            throw "invalid synthetic runtime pack: $runtimePack"
        }

        $frameworkName = $Matches.Name.Replace(".Runtime.win-x64", "")
        if ($frameworkName -ceq "Microsoft.WindowsDesktop.App") {
            $frameworkName = "Microsoft.WindowsDesktop.App.WindowsForms"
        }
        $frameworkReferences[$frameworkName] = [ordered]@{}
        $downloadDependencies[$Matches.Name] = [ordered]@{
            name = $Matches.Name
            version = "[$($Matches.Version), $($Matches.Version)]"
        }
    }

    foreach ($dependency in $DownloadOnlyDependencies) {
        if ($dependency -is [string]) {
            if ($dependency -notmatch `
                '^(?<Name>Microsoft\..*\.App\.Runtime\.win-x64)/(?<Version>[^/]+)$') {
                throw "invalid synthetic download dependency: $dependency"
            }

            $name = $Matches.Name
            $version = "[$($Matches.Version), $($Matches.Version)]"
        }
        else {
            $name = [string]$dependency.Name
            $version = [string]$dependency.Version
        }

        if ($downloadDependencies.Contains($name) `
            -and $downloadDependencies[$name].version -cne $version) {
            throw "conflicting synthetic download dependency: $name"
        }

        $downloadDependencies[$name] = [ordered]@{
            name = $name
            version = $version
        }
    }

    $document = [ordered]@{
        version = 3
        targets = [ordered]@{}
        libraries = [ordered]@{}
        project = [ordered]@{
            frameworks = [ordered]@{
                "net10.0-windows7.0" = [ordered]@{
                    downloadDependencies = @($downloadDependencies.Values)
                    frameworkReferences = $frameworkReferences
                }
            }
        }
    }
    [void](New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path))
    [IO.File]::WriteAllText(
        $Path,
        ($document | ConvertTo-Json -Depth 8))
}

function Get-Option {
    param(
        [hashtable]$Options,
        [string]$Name,
        $Default
    )

    if ($Options.ContainsKey($Name)) {
        return $Options[$Name]
    }

    return $Default
}

function New-ToolchainFixture {
    param(
        [string]$Name,
        [hashtable]$Options = @{}
    )

    $root = Join-Path $temporaryRoot $Name
    $relation = Get-Option $Options "RootRelation" "separate"
    $privateRoot = Join-Path $root "private"
    $externalRoot = Join-Path $root "external"
    if ($relation -ceq "equal") {
        $externalRoot = $privateRoot
    }
    elseif ($relation -ceq "external-nested") {
        $externalRoot = Join-Path $privateRoot "external"
    }
    elseif ($relation -ceq "private-nested") {
        $privateRoot = Join-Path $externalRoot "private"
    }

    $privateSdkRoot = if (Get-Option $Options "PrivateSdkOutside" $false) {
        Join-Path $root "outside-private-sdk"
    }
    else {
        Join-Path $privateRoot "sdk"
    }
    $externalSdkRoot = if (Get-Option $Options "ExternalSdkOutside" $false) {
        Join-Path $root "outside-external-sdk"
    }
    else {
        Join-Path $externalRoot "sdk"
    }

    $privateSdkMode = Get-Option $Options "PrivateSdkMode" "one"
    $privateSdkVersion = Get-Option $Options "PrivateSdkVersion" "10.0.100"
    $privateSdkLines = if ($privateSdkMode -ceq "zero") {
        @()
    }
    elseif ($privateSdkMode -ceq "multiple") {
        @(
            "10.0.100 [$privateSdkRoot]",
            "10.0.200 [$privateSdkRoot]")
    }
    else {
        @("$privateSdkVersion [$privateSdkRoot]")
    }

    $externalSdkMode = Get-Option $Options "ExternalSdkMode" "newer"
    $externalSdkLines = if ($externalSdkMode -ceq "missing") {
        @()
    }
    elseif ($externalSdkMode -ceq "same") {
        @("10.0.100 [$externalSdkRoot]")
    }
    elseif ($externalSdkMode -ceq "preview") {
        @("10.0.500-preview.1 [$externalSdkRoot]")
    }
    else {
        @("10.0.400 [$externalSdkRoot]")
    }

    $privateCapture = Join-Path $root "private-calls.txt"
    $externalCapture = Join-Path $root "external-calls.txt"
    $privateLauncher = New-FakeDotnet `
        -Root $privateRoot `
        -Version (Get-Option $Options "PrivateVersion" "10.0.100") `
        -SdkLines $privateSdkLines `
        -MsBuildVersion (Get-Option $Options "MsBuildVersion" "10.0.100") `
        -MsBuildSdksPath (Get-Option $Options "MsBuildSdksPath" (
            (Join-Path $privateRoot "sdk/10.0.100/Sdks"))) `
        -CapturePath $privateCapture

    $externalLauncher = if ($relation -ceq "equal") {
        $privateLauncher
    }
    else {
        New-FakeDotnet `
            -Root $externalRoot `
            -Version "10.0.400" `
            -SdkLines $externalSdkLines `
            -MsBuildVersion "10.0.400" `
            -MsBuildSdksPath (Join-Path $externalRoot "sdk/10.0.400/Sdks") `
            -CapturePath $externalCapture
    }

    $requiredPacks = @(
        "Microsoft.NETCore.App.Runtime.win-x64/10.0.0",
        "Microsoft.WindowsDesktop.App.Runtime.win-x64/10.0.0")
    $baselinePacks = @(Get-Option $Options "BaselinePacks" $requiredPacks)
    $candidatePacks = @(Get-Option $Options "CandidatePacks" $baselinePacks)
    $defaultDownloadOnlyDependencies = @(
        "Microsoft.AspNetCore.App.Runtime.win-x64/10.0.0")
    $baselineDownloadOnlyDependencies = @(Get-Option `
        $Options `
        "BaselineDownloadOnlyDependencies" `
        $defaultDownloadOnlyDependencies)
    $candidateDownloadOnlyDependencies = @(Get-Option `
        $Options `
        "CandidateDownloadOnlyDependencies" `
        $baselineDownloadOnlyDependencies)
    $baselineAssets = Join-Path $root "baseline/project.assets.json"
    $candidateAssets = Join-Path $root "candidate/project.assets.json"
    Write-AssetsFile `
        -Path $baselineAssets `
        -RuntimePacks $baselinePacks `
        -DownloadOnlyDependencies $baselineDownloadOnlyDependencies
    Write-AssetsFile `
        -Path $candidateAssets `
        -RuntimePacks $candidatePacks `
        -DownloadOnlyDependencies $candidateDownloadOnlyDependencies

    return [pscustomobject]@{
        DotnetPath = $privateLauncher
        ExternalDotnetPath = $externalLauncher
        Project = $project
        BaselineAssetsPath = [IO.Path]::GetFullPath($baselineAssets)
        CandidateAssetsPath = [IO.Path]::GetFullPath($candidateAssets)
        PrivateCapture = $privateCapture
        ExternalCapture = $externalCapture
    }
}

function Invoke-ToolchainAssertion {
    param([object]$Fixture)

    & $assertion `
        -DotnetPath $Fixture.DotnetPath `
        -ExternalDotnetPath $Fixture.ExternalDotnetPath `
        -Project $Fixture.Project `
        -BaselineAssetsPath $Fixture.BaselineAssetsPath `
        -CandidateAssetsPath $Fixture.CandidateAssetsPath
}

function Assert-Rejection {
    param(
        [string]$Name,
        [object]$Fixture,
        [string]$Expected
    )

    $diagnostic = $null
    $failureStack = $null
    try {
        $null = Invoke-ToolchainAssertion -Fixture $Fixture
    }
    catch {
        $diagnostic = $_.Exception.Message
        $failureStack = $_.ScriptStackTrace
    }

    if ($diagnostic -cne $Expected) {
        throw "$Name returned an unexpected diagnostic. Expected: $Expected Actual: $diagnostic Stack: $failureStack"
    }

    $script:passedControls++
}

function Invoke-SyntheticControls {
    param([int]$Pass)

    $privatePathDiagnostic = (
        "private dotnet path must be an absolute regular non-reparse executable file")
    $externalPathDiagnostic = (
        "external dotnet path must be an absolute regular non-reparse executable file")

    $fixture = New-ToolchainFixture "pass-$Pass-private-blank"
    $fixture.DotnetPath = " "
    Assert-Rejection "blank private launcher" $fixture $privatePathDiagnostic

    $fixture = New-ToolchainFixture "pass-$Pass-private-relative"
    $fixture.DotnetPath = "relative-dotnet"
    Assert-Rejection "relative private launcher" $fixture $privatePathDiagnostic

    $fixture = New-ToolchainFixture "pass-$Pass-private-missing"
    $fixture.DotnetPath = Join-Path $temporaryRoot "missing-dotnet.ps1"
    Assert-Rejection "missing private launcher" $fixture $privatePathDiagnostic

    $fixture = New-ToolchainFixture "pass-$Pass-private-empty"
    [IO.File]::WriteAllBytes($fixture.DotnetPath, [byte[]]::new(0))
    Assert-Rejection "empty private launcher" $fixture $privatePathDiagnostic

    $fixture = New-ToolchainFixture "pass-$Pass-private-non-executable"
    if ($IsWindows) {
        $nonExecutable = Join-Path (Split-Path $fixture.DotnetPath) "dotnet.txt"
        [IO.File]::Copy($fixture.DotnetPath, $nonExecutable)
        $fixture.DotnetPath = $nonExecutable
    }
    else {
        Set-LauncherExecutable -Path $fixture.DotnetPath -Executable $false
    }
    Assert-Rejection "non-executable private launcher" $fixture $privatePathDiagnostic

    $fixture = New-ToolchainFixture "pass-$Pass-private-reparse"
    $privateLink = Join-Path (Split-Path $fixture.DotnetPath) "dotnet-link.ps1"
    [void](New-Item -ItemType SymbolicLink -Path $privateLink -Target $fixture.DotnetPath)
    $fixture.DotnetPath = $privateLink
    Assert-Rejection "reparse private launcher" $fixture $privatePathDiagnostic

    $fixture = New-ToolchainFixture "pass-$Pass-private-reparse-parent"
    $privateTargetRoot = Split-Path -Parent $fixture.DotnetPath
    $privateParentLink = Join-Path (Split-Path -Parent $privateTargetRoot) (
        "private-parent-link-" + [Guid]::NewGuid().ToString("N"))
    if (New-DirectorySymlink -Path $privateParentLink -Target $privateTargetRoot) {
        $fixture.DotnetPath = Join-Path $privateParentLink (
            Split-Path -Leaf $fixture.DotnetPath)
        Assert-Rejection `
            "reparse private launcher parent" `
            $fixture `
            $privatePathDiagnostic
    }

    $fixture = New-ToolchainFixture "pass-$Pass-external-missing"
    $fixture.ExternalDotnetPath = Join-Path $temporaryRoot "missing-external-dotnet.ps1"
    Assert-Rejection "missing external launcher" $fixture $externalPathDiagnostic

    $fixture = New-ToolchainFixture "pass-$Pass-external-blank"
    $fixture.ExternalDotnetPath = " "
    Assert-Rejection "blank external launcher" $fixture $externalPathDiagnostic

    $fixture = New-ToolchainFixture "pass-$Pass-external-relative"
    $fixture.ExternalDotnetPath = "relative-dotnet"
    Assert-Rejection "relative external launcher" $fixture $externalPathDiagnostic

    $fixture = New-ToolchainFixture "pass-$Pass-external-empty"
    [IO.File]::WriteAllBytes($fixture.ExternalDotnetPath, [byte[]]::new(0))
    Assert-Rejection "empty external launcher" $fixture $externalPathDiagnostic

    $fixture = New-ToolchainFixture "pass-$Pass-external-non-executable"
    if ($IsWindows) {
        $nonExecutable = Join-Path (Split-Path $fixture.ExternalDotnetPath) "dotnet.txt"
        [IO.File]::Copy($fixture.ExternalDotnetPath, $nonExecutable)
        $fixture.ExternalDotnetPath = $nonExecutable
    }
    else {
        Set-LauncherExecutable -Path $fixture.ExternalDotnetPath -Executable $false
    }
    Assert-Rejection "non-executable external launcher" $fixture $externalPathDiagnostic

    $fixture = New-ToolchainFixture "pass-$Pass-external-reparse"
    $externalLink = Join-Path (Split-Path $fixture.ExternalDotnetPath) "dotnet-link.ps1"
    [void](New-Item -ItemType SymbolicLink -Path $externalLink -Target $fixture.ExternalDotnetPath)
    $fixture.ExternalDotnetPath = $externalLink
    Assert-Rejection "reparse external launcher" $fixture $externalPathDiagnostic

    $fixture = New-ToolchainFixture "pass-$Pass-external-reparse-parent"
    $externalTargetRoot = Split-Path -Parent $fixture.ExternalDotnetPath
    $externalParentLink = Join-Path (Split-Path -Parent $externalTargetRoot) (
        "external-parent-link-" + [Guid]::NewGuid().ToString("N"))
    if (New-DirectorySymlink -Path $externalParentLink -Target $externalTargetRoot) {
        $fixture.ExternalDotnetPath = Join-Path $externalParentLink (
            Split-Path -Leaf $fixture.ExternalDotnetPath)
        Assert-Rejection `
            "reparse external launcher parent" `
            $fixture `
            $externalPathDiagnostic
    }

    Assert-Rejection `
        "private CLI mismatch" `
        (New-ToolchainFixture "pass-$Pass-cli-version" @{
            PrivateVersion = "10.0.200"
        }) `
        "private dotnet CLI version must be exactly 10.0.100"

    Assert-Rejection `
        "private SDK version mismatch" `
        (New-ToolchainFixture "pass-$Pass-private-sdk-version" @{
            PrivateSdkVersion = "10.0.200"
        }) `
        "private dotnet SDK must be exactly 10.0.100"

    Assert-Rejection `
        "zero private SDK entries" `
        (New-ToolchainFixture "pass-$Pass-zero-private-sdk" @{
            PrivateSdkMode = "zero"
        }) `
        "private dotnet root must report exactly one SDK entry"

    Assert-Rejection `
        "multiple private SDK entries" `
        (New-ToolchainFixture "pass-$Pass-multiple-private-sdk" @{
            PrivateSdkMode = "multiple"
        }) `
        "private dotnet root must report exactly one SDK entry"

    Assert-Rejection `
        "private SDK outside root" `
        (New-ToolchainFixture "pass-$Pass-private-sdk-outside" @{
            PrivateSdkOutside = $true
        }) `
        "private dotnet SDK path must be beneath the private root"

    Assert-Rejection `
        "MSBuild SDK mismatch" `
        (New-ToolchainFixture "pass-$Pass-msbuild-version" @{
            MsBuildVersion = "10.0.200"
        }) `
        "ScreenFix MSBuild NETCoreSdkVersion must be exactly 10.0.100"

    Assert-Rejection `
        "MSBuild SDKs path outside root" `
        (New-ToolchainFixture "pass-$Pass-msbuild-path" @{
            MsBuildSdksPath = (Join-Path $temporaryRoot "outside-msbuild/Sdks")
        }) `
        "ScreenFix MSBuild MSBuildSDKsPath must be beneath the private root"

    Assert-Rejection `
        "external stable SDK missing" `
        (New-ToolchainFixture "pass-$Pass-external-missing-sdk" @{
            ExternalSdkMode = "missing"
        }) `
        "external dotnet root must report a newer stable .NET 10 SDK"

    Assert-Rejection `
        "external SDK is not newer" `
        (New-ToolchainFixture "pass-$Pass-external-same-sdk" @{
            ExternalSdkMode = "same"
        }) `
        "external dotnet root must report a newer stable .NET 10 SDK"

    Assert-Rejection `
        "external SDK is prerelease" `
        (New-ToolchainFixture "pass-$Pass-external-preview-sdk" @{
            ExternalSdkMode = "preview"
        }) `
        "external dotnet root must report a newer stable .NET 10 SDK"

    Assert-Rejection `
        "external SDK outside root" `
        (New-ToolchainFixture "pass-$Pass-external-sdk-outside" @{
            ExternalSdkOutside = $true
        }) `
        "external dotnet SDK path must be beneath the external root"

    foreach ($relationCase in @(
            @{ Name = "equal roots"; Value = "equal" },
            @{ Name = "external nested in private"; Value = "external-nested" },
            @{ Name = "private nested in external"; Value = "private-nested" })) {
        Assert-Rejection `
            $relationCase.Name `
            (New-ToolchainFixture "pass-$Pass-roots-$($relationCase.Value)" @{
                RootRelation = $relationCase.Value
            }) `
            "private and external dotnet roots must be fully separate"
    }

    $requiredPacks = @(
        "Microsoft.NETCore.App.Runtime.win-x64/10.0.0",
        "Microsoft.WindowsDesktop.App.Runtime.win-x64/10.0.0")
    Assert-Rejection `
        "runtime pack version" `
        (New-ToolchainFixture "pass-$Pass-runtime-version" @{
            BaselinePacks = @(
                "Microsoft.NETCore.App.Runtime.win-x64/10.0.1",
                "Microsoft.WindowsDesktop.App.Runtime.win-x64/10.0.0")
            CandidatePacks = @(
                "Microsoft.NETCore.App.Runtime.win-x64/10.0.1",
                "Microsoft.WindowsDesktop.App.Runtime.win-x64/10.0.0")
        }) `
        "baseline assets contain a conflicting win-x64 runtime pack: Microsoft.NETCore.App.Runtime.win-x64/10.0.1"

    Assert-Rejection `
        "missing NETCore runtime pack" `
        (New-ToolchainFixture "pass-$Pass-missing-netcore" @{
            BaselinePacks = @(
                "Microsoft.WindowsDesktop.App.Runtime.win-x64/10.0.0")
            CandidatePacks = @(
                "Microsoft.WindowsDesktop.App.Runtime.win-x64/10.0.0")
        }) `
        "baseline assets must contain Microsoft.NETCore.App.Runtime.win-x64/10.0.0"

    Assert-Rejection `
        "missing Windows Desktop runtime pack" `
        (New-ToolchainFixture "pass-$Pass-missing-desktop" @{
            BaselinePacks = @(
                "Microsoft.NETCore.App.Runtime.win-x64/10.0.0")
            CandidatePacks = @(
                "Microsoft.NETCore.App.Runtime.win-x64/10.0.0")
        }) `
        "baseline assets must contain Microsoft.WindowsDesktop.App.Runtime.win-x64/10.0.0"

    Assert-Rejection `
        "additional runtime pack" `
        (New-ToolchainFixture "pass-$Pass-additional-pack" @{
            BaselinePacks = $requiredPacks + @(
                "Microsoft.AspNetCore.App.Runtime.win-x64/10.0.0")
            CandidatePacks = $requiredPacks + @(
                "Microsoft.AspNetCore.App.Runtime.win-x64/10.0.0")
        }) `
        "baseline assets contain a conflicting win-x64 runtime pack: Microsoft.AspNetCore.App.Runtime.win-x64/10.0.0"

    Assert-Rejection `
        "baseline candidate mismatch" `
        (New-ToolchainFixture "pass-$Pass-pack-mismatch" @{
            BaselinePacks = $requiredPacks
            CandidatePacks = @(
                "Microsoft.NETCore.App.Runtime.win-x64/10.0.1",
                "Microsoft.WindowsDesktop.App.Runtime.win-x64/10.0.0")
        }) `
        "baseline and candidate win-x64 runtime-pack sets must match"

    $aspNetRuntimePack = "Microsoft.AspNetCore.App.Runtime.win-x64"
    Assert-Rejection `
        "download-only runtime version" `
        (New-ToolchainFixture "pass-$Pass-download-version" @{
            BaselineDownloadOnlyDependencies = @(
                "$aspNetRuntimePack/10.0.1")
            CandidateDownloadOnlyDependencies = @(
                "$aspNetRuntimePack/10.0.1")
        }) `
        "baseline assets contain a conflicting win-x64 runtime download dependency: $aspNetRuntimePack/10.0.1"

    Assert-Rejection `
        "non-fixed download-only runtime version" `
        (New-ToolchainFixture "pass-$Pass-download-range" @{
            BaselineDownloadOnlyDependencies = @([pscustomobject]@{
                Name = $aspNetRuntimePack
                Version = "[10.0.0, )"
            })
            CandidateDownloadOnlyDependencies = @([pscustomobject]@{
                Name = $aspNetRuntimePack
                Version = "[10.0.0, )"
            })
        }) `
        "baseline assets contain a non-fixed win-x64 runtime download dependency: $aspNetRuntimePack/[10.0.0, )"

    Assert-Rejection `
        "download-only runtime presence mismatch" `
        (New-ToolchainFixture "pass-$Pass-download-presence" @{
            BaselineDownloadOnlyDependencies = @(
                "$aspNetRuntimePack/10.0.0")
            CandidateDownloadOnlyDependencies = @()
        }) `
        "baseline and candidate win-x64 runtime download-dependency sets must match"

    Assert-Rejection `
        "download-only runtime name mismatch" `
        (New-ToolchainFixture "pass-$Pass-download-name" @{
            BaselineDownloadOnlyDependencies = @(
                "$aspNetRuntimePack/10.0.0")
            CandidateDownloadOnlyDependencies = @(
                "Microsoft.Other.App.Runtime.win-x64/10.0.0")
        }) `
        "baseline and candidate win-x64 runtime download-dependency sets must match"

    Assert-Rejection `
        "download-only runtime version mismatch" `
        (New-ToolchainFixture "pass-$Pass-download-version-mismatch" @{
            BaselineDownloadOnlyDependencies = @(
                "$aspNetRuntimePack/10.0.0")
            CandidateDownloadOnlyDependencies = @(
                "$aspNetRuntimePack/10.0.1")
        }) `
        "baseline and candidate win-x64 runtime download-dependency sets must match"

    $fixture = New-ToolchainFixture "pass-$Pass-valid"
    $savedPath = $env:PATH
    $savedDotnetRoot = $env:DOTNET_ROOT
    $output = @(Invoke-ToolchainAssertion -Fixture $fixture)
    if ($env:PATH -cne $savedPath -or $env:DOTNET_ROOT -cne $savedDotnetRoot) {
        throw "valid assertion changed PATH or DOTNET_ROOT"
    }

    $expectedPrivateCalls = @(
        "--version",
        "--list-sdks",
        "--info",
        "msbuild|$project|-nologo|-getProperty:NETCoreSdkVersion",
        "msbuild|$project|-nologo|-getProperty:MSBuildSDKsPath")
    $privateCalls = @(Get-Content -LiteralPath $fixture.PrivateCapture)
    if (($privateCalls -join "`n") -cne ($expectedPrivateCalls -join "`n")) {
        throw "valid assertion did not execute the exact private dotnet commands"
    }

    $externalCalls = @(Get-Content -LiteralPath $fixture.ExternalCapture)
    if ($externalCalls.Count -ne 1 -or $externalCalls[0] -cne "--list-sdks") {
        throw "valid assertion did not execute the exact external dotnet command"
    }

    $joinedOutput = $output -join "`n"
    foreach ($expectedLog in @(
            "Private dotnet CLI version: 10.0.100",
            "ScreenFix MSBuild NETCoreSdkVersion: 10.0.100",
            "External stable .NET 10 SDK: 10.0.400",
            "Microsoft.NETCore.App.Runtime.win-x64/10.0.0",
            "Microsoft.WindowsDesktop.App.Runtime.win-x64/10.0.0",
            "Microsoft.AspNetCore.App.Runtime.win-x64/10.0.0")) {
        if (-not $joinedOutput.Contains($expectedLog)) {
            throw "valid assertion omitted required log: $expectedLog"
        }
    }

    $script:passedControls++
}

try {
    [void](New-Item -ItemType Directory -Path $temporaryRoot)
    Invoke-SyntheticControls -Pass 1
    Invoke-SyntheticControls -Pass 2
    Write-Output "pinned toolchain assertion controls passed twice ($passedControls total controls)"
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
