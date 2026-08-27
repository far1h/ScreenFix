param(
    [Parameter(Mandatory = $true)]
    [string]$DotnetPath,
    [Parameter(Mandatory = $true)]
    [string]$ExternalDotnetPath,
    [Parameter(Mandatory = $true)]
    [string]$Project
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$requiredSdkVersion = "10.0.100"
$pathComparison = if ($IsWindows) {
    [StringComparison]::OrdinalIgnoreCase
}
else {
    [StringComparison]::Ordinal
}

function Test-ExecutableFile {
    param([IO.FileInfo]$File)

    if ($IsWindows) {
        return @(".exe", ".com", ".cmd", ".bat", ".ps1") -ccontains `
            $File.Extension.ToLowerInvariant()
    }

    $executeMask = [int]([IO.UnixFileMode]::UserExecute -bor `
        [IO.UnixFileMode]::GroupExecute -bor `
        [IO.UnixFileMode]::OtherExecute)
    $mode = [int][IO.File]::GetUnixFileMode($File.FullName)
    return ($mode -band $executeMask) -ne 0
}

function Test-PathHasReparsePoint {
    param([string]$Path)

    $current = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetPathRoot($current)
    while (-not [string]::IsNullOrWhiteSpace($current)) {
        try {
            $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
        }
        catch {
            return $true
        }

        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            return $true
        }
        if ($current.Equals($root, $pathComparison)) {
            return $false
        }

        $parent = [IO.Path]::GetDirectoryName($current)
        if ([string]::IsNullOrWhiteSpace($parent) `
            -or $parent.Equals($current, $pathComparison)) {
            return $true
        }
        $current = $parent
    }

    return $true
}

function Resolve-LauncherPath {
    param(
        [string]$Path,
        [ValidateSet("private", "external")]
        [string]$Name
    )

    $diagnostic = (
        "$Name dotnet path must be an absolute regular non-reparse executable file")
    if ([string]::IsNullOrWhiteSpace($Path) `
        -or -not [IO.Path]::IsPathFullyQualified($Path)) {
        throw $diagnostic
    }

    try {
        $normalized = [IO.Path]::GetFullPath($Path)
        $item = Get-Item -LiteralPath $normalized -Force -ErrorAction SilentlyContinue
    }
    catch {
        throw $diagnostic
    }

    if ($null -eq $item `
        -or $item -isnot [IO.FileInfo] `
        -or $item.Length -le 0 `
        -or (Test-PathHasReparsePoint -Path $normalized) `
        -or -not (Test-ExecutableFile -File $item)) {
        throw $diagnostic
    }

    return $normalized
}

function Resolve-RegularFilePath {
    param(
        [string]$Path,
        [string]$Diagnostic
    )

    if ([string]::IsNullOrWhiteSpace($Path) `
        -or -not [IO.Path]::IsPathFullyQualified($Path)) {
        throw $Diagnostic
    }

    try {
        $normalized = [IO.Path]::GetFullPath($Path)
        $item = Get-Item -LiteralPath $normalized -Force -ErrorAction SilentlyContinue
    }
    catch {
        throw $Diagnostic
    }

    if ($null -eq $item `
        -or $item -isnot [IO.FileInfo] `
        -or $item.Length -le 0 `
        -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw $Diagnostic
    }

    return $normalized
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
    return -not $relative.StartsWith($parentPrefix, $pathComparison) `
        -and -not $relative.StartsWith($alternatePrefix, $pathComparison)
}

function Invoke-Dotnet {
    param(
        [string]$Launcher,
        [string[]]$Arguments,
        [string]$Description
    )

    $output = @(& $Launcher @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "$Description failed with exit code $exitCode"
    }

    return @($output | ForEach-Object { $_.ToString() })
}

function Get-NonemptyLines {
    param([string[]]$Output)

    return @($Output | Where-Object { $null -ne $_ } | ForEach-Object {
        $_.Trim()
    } | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_)
    })
}

function Get-SingleLine {
    param(
        [string[]]$Output,
        [string]$Diagnostic
    )

    $lines = @(Get-NonemptyLines -Output $Output)
    if ($lines.Count -ne 1) {
        throw $Diagnostic
    }

    return $lines[0]
}

function ConvertFrom-SdkListing {
    param(
        [string[]]$Output,
        [string]$Diagnostic
    )

    $entries = [Collections.Generic.List[object]]::new()
    foreach ($line in @(Get-NonemptyLines -Output $Output)) {
        if ($line -notmatch `
            '^(?<Version>\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?) \[(?<Path>.+)\]$') {
            throw $Diagnostic
        }

        [void]$entries.Add([pscustomobject]@{
            Version = $Matches.Version
            Path = [IO.Path]::GetFullPath($Matches.Path)
        })
    }

    return $entries.ToArray()
}

$DotnetPath = Resolve-LauncherPath -Path $DotnetPath -Name "private"
$ExternalDotnetPath = Resolve-LauncherPath `
    -Path $ExternalDotnetPath `
    -Name "external"
$privateRoot = [IO.Path]::GetFullPath((Split-Path -Parent $DotnetPath))
$externalRoot = [IO.Path]::GetFullPath((Split-Path -Parent $ExternalDotnetPath))
if ($privateRoot.Equals($externalRoot, $pathComparison) `
    -or (Test-PathBeneath -Parent $privateRoot -Child $externalRoot) `
    -or (Test-PathBeneath -Parent $externalRoot -Child $privateRoot)) {
    throw "private and external dotnet roots must be fully separate"
}

$Project = Resolve-RegularFilePath `
    -Path $Project `
    -Diagnostic "project must be the real ScreenFix app project"
$expectedProject = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "../src/ScreenFix.App/ScreenFix.App.csproj"))
if (-not $Project.Equals($expectedProject, $pathComparison)) {
    throw "project must be the real ScreenFix app project"
}

$versionOutput = Invoke-Dotnet `
    -Launcher $DotnetPath `
    -Arguments @("--version") `
    -Description "private dotnet --version"
$privateVersion = Get-SingleLine `
    -Output $versionOutput `
    -Diagnostic "private dotnet CLI version must be exactly 10.0.100"
if ($privateVersion -cne $requiredSdkVersion) {
    throw "private dotnet CLI version must be exactly 10.0.100"
}
Write-Output "Private dotnet CLI version: $privateVersion"

$privateSdkOutput = Invoke-Dotnet `
    -Launcher $DotnetPath `
    -Arguments @("--list-sdks") `
    -Description "private dotnet --list-sdks"
$privateSdks = @(ConvertFrom-SdkListing `
    -Output $privateSdkOutput `
    -Diagnostic "private dotnet SDK listing is malformed")
if ($privateSdks.Count -ne 1) {
    throw "private dotnet root must report exactly one SDK entry"
}
if ($privateSdks[0].Version -cne $requiredSdkVersion) {
    throw "private dotnet SDK must be exactly 10.0.100"
}
if (-not (Test-PathBeneath -Parent $privateRoot -Child $privateSdks[0].Path)) {
    throw "private dotnet SDK path must be beneath the private root"
}
Write-Output "Private dotnet SDK: $($privateSdks[0].Version) [$($privateSdks[0].Path)]"

$privateInfo = Invoke-Dotnet `
    -Launcher $DotnetPath `
    -Arguments @("--info") `
    -Description "private dotnet --info"
Write-Output "Private dotnet info:"
$privateInfo | Write-Output

$msBuildVersionOutput = Invoke-Dotnet `
    -Launcher $DotnetPath `
    -Arguments @(
        "msbuild",
        $Project,
        "-nologo",
        "-getProperty:NETCoreSdkVersion") `
    -Description "ScreenFix MSBuild NETCoreSdkVersion probe"
$msBuildVersion = Get-SingleLine `
    -Output $msBuildVersionOutput `
    -Diagnostic "ScreenFix MSBuild NETCoreSdkVersion must be exactly 10.0.100"
if ($msBuildVersion -cne $requiredSdkVersion) {
    throw "ScreenFix MSBuild NETCoreSdkVersion must be exactly 10.0.100"
}
Write-Output "ScreenFix MSBuild NETCoreSdkVersion: $msBuildVersion"

$msBuildSdksOutput = Invoke-Dotnet `
    -Launcher $DotnetPath `
    -Arguments @(
        "msbuild",
        $Project,
        "-nologo",
        "-getProperty:MSBuildSDKsPath") `
    -Description "ScreenFix MSBuild MSBuildSDKsPath probe"
$msBuildSdksPath = Get-SingleLine `
    -Output $msBuildSdksOutput `
    -Diagnostic "ScreenFix MSBuild MSBuildSDKsPath must be beneath the private root"
try {
    $msBuildSdksPath = [IO.Path]::GetFullPath($msBuildSdksPath)
}
catch {
    throw "ScreenFix MSBuild MSBuildSDKsPath must be beneath the private root"
}
if (-not (Test-PathBeneath -Parent $privateRoot -Child $msBuildSdksPath)) {
    throw "ScreenFix MSBuild MSBuildSDKsPath must be beneath the private root"
}
Write-Output "ScreenFix MSBuild MSBuildSDKsPath: $msBuildSdksPath"

$externalSdkOutput = Invoke-Dotnet `
    -Launcher $ExternalDotnetPath `
    -Arguments @("--list-sdks") `
    -Description "external dotnet --list-sdks"
$externalSdks = @(ConvertFrom-SdkListing `
    -Output $externalSdkOutput `
    -Diagnostic "external dotnet SDK listing is malformed")
foreach ($sdk in $externalSdks) {
    if (-not (Test-PathBeneath -Parent $externalRoot -Child $sdk.Path)) {
        throw "external dotnet SDK path must be beneath the external root"
    }
}

$requiredVersion = [version]$requiredSdkVersion
$newerStableSdks = @($externalSdks | Where-Object {
    $_.Version -match '^10\.0\.\d+$' `
        -and [version]$_.Version -gt $requiredVersion
} | Sort-Object { [version]$_.Version } -Descending)
if ($newerStableSdks.Count -eq 0) {
    throw "external dotnet root must report a newer stable .NET 10 SDK"
}
Write-Output "External stable .NET 10 SDK: $($newerStableSdks[0].Version)"
