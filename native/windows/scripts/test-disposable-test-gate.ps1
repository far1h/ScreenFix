$ErrorActionPreference = "Stop"

$scriptUnderTest = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "test-windows-native.ps1"))
$workflow = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "../../../.github/workflows/windows-native.yml"))
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) (
    "screenfix-disposable-gate-" + [Guid]::NewGuid().ToString("N"))
$capturePath = Join-Path $temporaryRoot "dotnet-calls.txt"
$fakeDotnet = Join-Path $temporaryRoot "dotnet.ps1"
$environmentNames = @(
    "CI",
    "GITHUB_ACTIONS",
    "SCREENFIX_RUNNER_ENVIRONMENT",
    "RUNNER_TEMP"
)

function Set-TestEnvironment {
    param([hashtable]$Values)

    foreach ($name in $environmentNames) {
        [Environment]::SetEnvironmentVariable($name, $Values[$name], "Process")
    }
}

function Invoke-Gate {
    param(
        [hashtable]$Environment,
        [switch]$AllowDisposableAccountMutation
    )

    Remove-Item -LiteralPath $capturePath -Force -ErrorAction SilentlyContinue
    Set-TestEnvironment $Environment
    if ($AllowDisposableAccountMutation) {
        & $scriptUnderTest `
            -DotnetPath $fakeDotnet `
            -AllowDisposableAccountMutation
    }
    else {
        & $scriptUnderTest -DotnetPath $fakeDotnet
    }

    if (-not (Test-Path -LiteralPath $capturePath -PathType Leaf)) {
        return @()
    }

    return @(Get-Content -LiteralPath $capturePath)
}

function Assert-RefusedBeforeTest {
    param(
        [string]$Name,
        [hashtable]$Environment
    )

    try {
        $null = Invoke-Gate `
            -Environment $Environment `
            -AllowDisposableAccountMutation
        throw "$Name did not refuse disposable-account mutation"
    }
    catch {
        if ($_.Exception.Message -notlike "disposable account mutation requires*") {
            throw
        }
    }

    if (Test-Path -LiteralPath $capturePath -PathType Leaf) {
        $testCalls = @(Get-Content -LiteralPath $capturePath | Where-Object {
            $_ -match '(^|\s)test(\s|$)'
        })
        if ($testCalls.Count -ne 0) {
            throw "$Name reached test execution before refusing mutation"
        }
    }
}

$savedEnvironment = @{}
foreach ($name in $environmentNames) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, "Process")
}

try {
    $null = New-Item -ItemType Directory -Path $temporaryRoot
    @(
        'param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Remaining)',
        "Add-Content -LiteralPath `"$capturePath`" -Value (`$Remaining -join ' ')",
        'exit 0'
    ) | Set-Content -LiteralPath $fakeDotnet -Encoding Utf8
    if (-not $IsWindows) {
        $mode = [IO.UnixFileMode]::UserRead -bor `
            [IO.UnixFileMode]::UserWrite -bor `
            [IO.UnixFileMode]::UserExecute
        [IO.File]::SetUnixFileMode($fakeDotnet, $mode)
    }

    $valid = @{
        CI = "true"
        GITHUB_ACTIONS = "true"
        SCREENFIX_RUNNER_ENVIRONMENT = "github-hosted"
        RUNNER_TEMP = [IO.Path]::GetFullPath($temporaryRoot)
    }

    $defaultCalls = Invoke-Gate -Environment $valid
    $defaultTests = @($defaultCalls | Where-Object { $_ -match '(^|\s)test(\s|$)' })
    $scriptText = Get-Content -LiteralPath $scriptUnderTest -Raw
    $ambientDotnetResolver = "Get-Command " + "dotnet"
    if ($scriptText.Contains($ambientDotnetResolver) `
        -or $scriptText -notmatch `
            '(?s)\[Parameter\(Mandatory\s*=\s*\$true\)\]\s*\[string\]\$DotnetPath') {
        throw "Windows native tests must require an absolute dotnet launcher"
    }
    if ($IsWindows) {
        if ($defaultTests.Count -ne 1 `
            -or $defaultTests[0] -notmatch 'ScreenFixCategory!=DisposableAccount') {
            throw "default Windows test filter must exclude DisposableAccount"
        }
    }
    elseif ($scriptText -notmatch '--filter\s+"\(FullyQualifiedName!~PublishedExecutableIconTests\)&\(ScreenFixCategory!=DisposableAccount\)"') {
        throw "default Windows test filter must exclude DisposableAccount"
    }

    $invalidCases = @(
        @{ Name = "missing CI"; Key = "CI"; Value = $null },
        @{ Name = "invalid CI"; Key = "CI"; Value = "TRUE" },
        @{ Name = "missing GITHUB_ACTIONS"; Key = "GITHUB_ACTIONS"; Value = $null },
        @{ Name = "invalid GITHUB_ACTIONS"; Key = "GITHUB_ACTIONS"; Value = "false" },
        @{ Name = "missing runner environment"; Key = "SCREENFIX_RUNNER_ENVIRONMENT"; Value = $null },
        @{ Name = "invalid runner environment"; Key = "SCREENFIX_RUNNER_ENVIRONMENT"; Value = "self-hosted" },
        @{ Name = "missing runner temp"; Key = "RUNNER_TEMP"; Value = $null },
        @{ Name = "relative runner temp"; Key = "RUNNER_TEMP"; Value = "relative-runner-temp" }
    )
    foreach ($case in $invalidCases) {
        $environment = $valid.Clone()
        $environment[$case.Key] = $case.Value
        Assert-RefusedBeforeTest -Name $case.Name -Environment $environment
    }

    $disposableCalls = Invoke-Gate `
        -Environment $valid `
        -AllowDisposableAccountMutation
    $disposableTests = @($disposableCalls | Where-Object {
        $_ -match '(^|\s)test(\s|$)'
    })
    if ($IsWindows) {
        if ($disposableTests.Count -ne 1 `
            -or $disposableTests[0] -notmatch 'ScreenFixCategory=DisposableAccount' `
            -or $disposableTests[0] -match 'ScreenFixCategory!=DisposableAccount') {
            throw "disposable invocation must select only the DisposableAccount trait"
        }
    }
    elseif ($scriptText -notmatch '--filter\s+"ScreenFixCategory=DisposableAccount"') {
        throw "disposable invocation must select only the DisposableAccount trait"
    }

    $workflowText = Get-Content -LiteralPath $workflow -Raw
    $workflowRequirements = @(
        'SCREENFIX_SOURCE_SHA: ${{ github.event_name == ''pull_request'' && github.event.pull_request.head.sha || github.sha }}',
        'ref: ${{ env.SCREENFIX_SOURCE_SHA }}',
        'actions/checkout@v7',
        'actions/setup-dotnet@v6',
        '${{ runner.temp }}\screenfix-external-dotnet',
        '${{ runner.temp }}\screenfix-dotnet-10.0.100',
        'dotnet-version: 10.0.x',
        'dotnet-quality: ga',
        'dotnet-version: 10.0.100',
        'SCREENFIX_EXTERNAL_DOTNET',
        'SCREENFIX_PRIVATE_DOTNET',
        'git rev-parse HEAD',
        '-DotnetPath $env:SCREENFIX_PRIVATE_DOTNET',
        '-ExternalDotnetPath $env:SCREENFIX_EXTERNAL_DOTNET')
    foreach ($requirement in $workflowRequirements) {
        if (-not $workflowText.Contains($requirement)) {
            throw "workflow is missing pinned-toolchain contract: $requirement"
        }
    }

    $externalSetupIndex = $workflowText.IndexOf(
        '${{ runner.temp }}\screenfix-external-dotnet')
    $privateSetupIndex = $workflowText.IndexOf(
        '${{ runner.temp }}\screenfix-dotnet-10.0.100')
    if ($externalSetupIndex -lt 0 -or $privateSetupIndex -le $externalSetupIndex) {
        throw "workflow must install the external SDK before the private SDK"
    }

    if ($workflowText -match '(?m)^\s*(?:run:\s*)?dotnet(?:\.exe)?\s') {
        throw "workflow must not invoke bare dotnet"
    }

    if (($workflowText | Select-String -Pattern 'SCREENFIX_RUNNER_ENVIRONMENT:' -AllMatches).Matches.Count -ne 1 `
        -or $workflowText -notmatch 'SCREENFIX_RUNNER_ENVIRONMENT:\s*\$\{\{ runner\.environment \}\}') {
        throw "workflow must map runner.environment once through SCREENFIX_RUNNER_ENVIRONMENT"
    }

    $gateIndex = $workflowText.IndexOf("test-disposable-test-gate.ps1")
    $disposableIndex = $workflowText.IndexOf("-AllowDisposableAccountMutation")
    if ($gateIndex -lt 0 -or $disposableIndex -le $gateIndex) {
        throw "workflow must run the gate regression before the disposable test step"
    }

    Write-Output "Disposable-account test gate regressions passed."
}
finally {
    Set-TestEnvironment $savedEnvironment
    Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
}
