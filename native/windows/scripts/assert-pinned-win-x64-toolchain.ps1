param(
    [Parameter(Mandatory = $true)]
    [string]$DotnetPath,
    [Parameter(Mandatory = $true)]
    [string]$ExternalDotnetPath,
    [Parameter(Mandatory = $true)]
    [string]$Project,
    [Parameter(Mandatory = $true)]
    [string]$BaselineAssetsPath,
    [Parameter(Mandatory = $true)]
    [string]$CandidateAssetsPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$requiredRuntimePacks = @(
    "Microsoft.NETCore.App.Runtime.win-x64/10.0.0",
    "Microsoft.WindowsDesktop.App.Runtime.win-x64/10.0.0")
$preflight = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "assert-pinned-win-x64-toolchain-preflight.ps1"))

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

function Get-RuntimePackState {
    param(
        [string]$AssetsPath,
        [string]$Name
    )

    try {
        $document = Get-Content -LiteralPath $AssetsPath -Raw |
            ConvertFrom-Json -AsHashtable -Depth 100
    }
    catch {
        throw "$Name assets are not valid project.assets.json"
    }

    if ($document -isnot [Collections.IDictionary] `
        -or -not $document.Contains("project") `
        -or $document.project -isnot [Collections.IDictionary] `
        -or -not $document.project.Contains("frameworks") `
        -or $document.project.frameworks -isnot [Collections.IDictionary]) {
        throw "$Name assets are not valid project.assets.json"
    }

    $activeRuntimePacks = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal)
    $downloadRuntimePacks = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal)
    foreach ($framework in $document.project.frameworks.Values) {
        if ($framework -isnot [Collections.IDictionary] `
            -or -not $framework.Contains("frameworkReferences") `
            -or $framework.frameworkReferences -isnot [Collections.IDictionary] `
            -or -not $framework.Contains("downloadDependencies")) {
            throw "$Name assets are not valid project.assets.json"
        }

        $downloadsByName = [Collections.Generic.Dictionary[string, string]]::new(
            [StringComparer]::Ordinal)
        foreach ($download in @($framework.downloadDependencies)) {
            if ($download -isnot [Collections.IDictionary] `
                -or -not $download.Contains("name")) {
                throw "$Name assets are not valid project.assets.json"
            }

            $downloadName = [string]$download.name
            if ($downloadName -cnotmatch `
                '^Microsoft\..*\.App\.Runtime\.win-x64$') {
                continue
            }
            if (-not $download.Contains("version")) {
                throw "$Name assets are not valid project.assets.json"
            }

            $versionRange = [string]$download.version
            if ($versionRange -notmatch `
                '^\[(?<Lower>\d+\.\d+\.\d+),\s*(?<Upper>\d+\.\d+\.\d+)\]$' `
                -or $Matches.Lower -cne $Matches.Upper) {
                throw "$Name assets contain a non-fixed win-x64 runtime download dependency: $downloadName/$versionRange"
            }

            $version = $Matches.Lower
            if ($downloadsByName.ContainsKey($downloadName)) {
                throw "$Name assets are not valid project.assets.json"
            }
            $downloadsByName.Add($downloadName, $version)
            [void]$downloadRuntimePacks.Add("$downloadName/$version")
        }

        foreach ($frameworkReference in $framework.frameworkReferences.Keys) {
            if ($frameworkReference -notmatch `
                '^(?<Base>Microsoft\..*?\.App)(?:\..+)?$') {
                continue
            }

            $runtimePackName = "$($Matches.Base).Runtime.win-x64"
            if (-not $downloadsByName.ContainsKey($runtimePackName)) {
                throw "$Name assets are not valid project.assets.json"
            }

            [void]$activeRuntimePacks.Add(
                "$runtimePackName/$($downloadsByName[$runtimePackName])")
        }
    }

    return [pscustomobject]@{
        ActivePacks = @($activeRuntimePacks | Sort-Object -CaseSensitive)
        DownloadPacks = @($downloadRuntimePacks | Sort-Object -CaseSensitive)
    }
}

function Assert-RuntimePacks {
    param(
        [string[]]$RuntimePacks,
        [string]$Name
    )

    $conflicts = @($RuntimePacks | Where-Object {
        $requiredRuntimePacks -cnotcontains $_
    })
    if ($conflicts.Count -gt 0) {
        throw "$Name assets contain a conflicting win-x64 runtime pack: $($conflicts[0])"
    }

    foreach ($requiredPack in $requiredRuntimePacks) {
        if ($RuntimePacks -cnotcontains $requiredPack) {
            throw "$Name assets must contain $requiredPack"
        }
    }
}

function Assert-RuntimeDownloadPacks {
    param(
        [string[]]$RuntimePacks,
        [string]$Name
    )

    foreach ($runtimePack in $RuntimePacks) {
        if ($runtimePack -notmatch '/10\.0\.0$') {
            throw "$Name assets contain a conflicting win-x64 runtime download dependency: $runtimePack"
        }
    }
}

& $preflight `
    -DotnetPath $DotnetPath `
    -ExternalDotnetPath $ExternalDotnetPath `
    -Project $Project |
    Write-Output

$BaselineAssetsPath = Resolve-RegularFilePath `
    -Path $BaselineAssetsPath `
    -Diagnostic "baseline assets path must be an absolute regular non-reparse nonempty file"
$CandidateAssetsPath = Resolve-RegularFilePath `
    -Path $CandidateAssetsPath `
    -Diagnostic "candidate assets path must be an absolute regular non-reparse nonempty file"

$baselineState = Get-RuntimePackState `
    -AssetsPath $BaselineAssetsPath `
    -Name "baseline"
$candidateState = Get-RuntimePackState `
    -AssetsPath $CandidateAssetsPath `
    -Name "candidate"
$packDifferences = @(Compare-Object `
    -ReferenceObject $baselineState.ActivePacks `
    -DifferenceObject $candidateState.ActivePacks `
    -CaseSensitive)
if ($packDifferences.Count -ne 0) {
    throw "baseline and candidate win-x64 runtime-pack sets must match"
}

Assert-RuntimePacks -RuntimePacks $baselineState.ActivePacks -Name "baseline"
Assert-RuntimePacks -RuntimePacks $candidateState.ActivePacks -Name "candidate"
$downloadDifferences = @(Compare-Object `
    -ReferenceObject $baselineState.DownloadPacks `
    -DifferenceObject $candidateState.DownloadPacks `
    -CaseSensitive)
if ($downloadDifferences.Count -ne 0) {
    throw "baseline and candidate win-x64 runtime download-dependency sets must match"
}

Assert-RuntimeDownloadPacks `
    -RuntimePacks $baselineState.DownloadPacks `
    -Name "baseline"
Assert-RuntimeDownloadPacks `
    -RuntimePacks $candidateState.DownloadPacks `
    -Name "candidate"
Write-Output "Validated win-x64 runtime packs:"
$baselineState.ActivePacks | Write-Output
Write-Output "Validated win-x64 runtime download dependencies:"
$baselineState.DownloadPacks | Write-Output
