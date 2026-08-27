Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$assertion = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "assert-windows-download-docs.ps1"))
$workflow = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "../../../.github/workflows/windows-native.yml"))
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) (
    "ScreenFix.WindowsDownloadDocsTests." + [Guid]::NewGuid().ToString("N"))
$passedControls = 0

function Write-Document {
    param(
        [string]$Name,
        [string]$Content
    )

    $path = Join-Path $temporaryRoot $Name
    [IO.File]::WriteAllText($path, $Content)
    return [IO.Path]::GetFullPath($path)
}

function Assert-Rejection {
    param(
        [string]$Name,
        [string]$Path,
        [string]$Expected
    )

    $diagnostic = $null
    try {
        & $assertion -ReadmePath $Path
    }
    catch {
        $diagnostic = $_.Exception.Message
    }

    if ($diagnostic -cne $Expected) {
        throw "$Name returned an unexpected diagnostic. Expected: $Expected Actual: $diagnostic"
    }

    $script:passedControls++
}

function Get-WorkflowEventPaths {
    param(
        [string]$Source,
        [string]$EventName
    )

    $pattern = (
        '(?ms)^  ' + [Text.RegularExpressions.Regex]::Escape($EventName) +
        ':\r?\n    paths:\r?\n(?<paths>(?:      - [^\r\n]+\r?\n)+)')
    $match = [Text.RegularExpressions.Regex]::Match($Source, $pattern)
    if (-not $match.Success) {
        throw "Windows workflow $EventName paths block is missing"
    }

    return $match.Groups['paths'].Value
}

$validDocument = @'
# ScreenFix

`ScreenFix-Windows-x64.exe` is the recommended smaller self-contained download.
`ScreenFix-Windows-x64-uncompressed.exe` is the behavior-identical uncompressed fallback
for startup or extraction trouble.
Neither download needs a separate .NET runtime, and there is no ZIP to extract.
Both target ordinary Intel or AMD x64 Windows.
'@

try {
    [void](New-Item -ItemType Directory -Path $temporaryRoot)

    $workflowSource = [IO.File]::ReadAllText($workflow)
    $pushPaths = Get-WorkflowEventPaths -Source $workflowSource -EventName "push"
    if (-not [Text.RegularExpressions.Regex]::IsMatch(
            $pushPaths,
            '(?m)^      - "README\.md"\r?$')) {
        throw "Windows workflow push paths must include README.md"
    }
    $passedControls++

    $pullRequestPaths = Get-WorkflowEventPaths `
        -Source $workflowSource `
        -EventName "pull_request"
    if (-not [Text.RegularExpressions.Regex]::IsMatch(
            $pullRequestPaths,
            '(?m)^      - "README\.md"\r?$')) {
        throw "Windows workflow pull_request paths must include README.md"
    }
    $passedControls++

    $validPath = Write-Document -Name "valid.md" -Content $validDocument
    $output = @(& $assertion -ReadmePath $validPath)
    if (($output -join "`n") -cne "Windows download documentation is current.") {
        throw "valid documentation returned unexpected output"
    }
    $passedControls++

    $missingRecommended = $validDocument.Replace(
        '`ScreenFix-Windows-x64.exe` is the recommended smaller self-contained download.',
        'Download the smaller package.')
    Assert-Rejection `
        -Name "missing recommended download" `
        -Path (Write-Document -Name "missing-recommended.md" -Content $missingRecommended) `
        -Expected "README must identify ScreenFix-Windows-x64.exe as the recommended smaller self-contained download"

    $fallbackPattern = (
        [Text.RegularExpressions.Regex]::Escape(
            '`ScreenFix-Windows-x64-uncompressed.exe` is the behavior-identical uncompressed fallback') +
        '\r?\n' +
        [Text.RegularExpressions.Regex]::Escape(
            'for startup or extraction trouble.'))
    $missingFallback = [Text.RegularExpressions.Regex]::Replace(
        $validDocument,
        $fallbackPattern,
        'Use another download if startup fails.')
    Assert-Rejection `
        -Name "missing fallback download" `
        -Path (Write-Document -Name "missing-fallback.md" -Content $missingFallback) `
        -Expected "README must identify ScreenFix-Windows-x64-uncompressed.exe as the behavior-identical uncompressed fallback for startup or extraction trouble"

    $missingRuntimeContract = $validDocument.Replace(
        'Neither download needs a separate .NET runtime, and there is no ZIP to extract.',
        'The downloads are ready to use.')
    Assert-Rejection `
        -Name "missing runtime and archive contract" `
        -Path (Write-Document -Name "missing-runtime.md" -Content $missingRuntimeContract) `
        -Expected "README must state that neither Windows download needs a separate .NET runtime and there is no ZIP to extract"

    $missingArchitecture = $validDocument.Replace(
        'Both target ordinary Intel or AMD x64 Windows.',
        'Both target Windows.')
    Assert-Rejection `
        -Name "missing architecture contract" `
        -Path (Write-Document -Name "missing-architecture.md" -Content $missingArchitecture) `
        -Expected "README must state that both downloads target ordinary Intel or AMD x64 Windows"

    $wrongOrder = @'
`ScreenFix-Windows-x64-uncompressed.exe` is the behavior-identical uncompressed fallback for startup or extraction trouble.
`ScreenFix-Windows-x64.exe` is the recommended smaller self-contained download.
Neither download needs a separate .NET runtime, and there is no ZIP to extract.
Both target ordinary Intel or AMD x64 Windows.
'@
    Assert-Rejection `
        -Name "fallback listed first" `
        -Path (Write-Document -Name "wrong-order.md" -Content $wrongOrder) `
        -Expected "README must name the recommended Windows download before the fallback"

    $legacyZip = "$validDocument`nDownload ``ScreenFix-windows-x64.zip``."
    Assert-Rejection `
        -Name "legacy ZIP" `
        -Path (Write-Document -Name "legacy-zip.md" -Content $legacyZip) `
        -Expected "README must not name the obsolete ScreenFix-windows-x64.zip download"

    $legacyExecutable = "$validDocument`nRun ``ScreenFix.exe``."
    Assert-Rejection `
        -Name "bare legacy executable" `
        -Path (Write-Document -Name "legacy-executable.md" -Content $legacyExecutable) `
        -Expected "README must not instruct users to download or run bare ScreenFix.exe"
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}

Write-Output "Windows download documentation tests passed ($passedControls controls)"
