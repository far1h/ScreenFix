Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$publishSourcePath = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "publish-win-x64.ps1"))
$preflightSourcePath = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "assert-pinned-win-x64-toolchain-preflight.ps1"))
$fullAssertionSourcePath = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "assert-pinned-win-x64-toolchain.ps1"))
$temporaryBase = if (-not $IsWindows `
    -and (Test-Path -LiteralPath "/private/tmp" -PathType Container)) {
    "/private/tmp"
}
else {
    [IO.Path]::GetTempPath()
}
$temporaryRoot = Join-Path $temporaryBase (
    "ScreenFix.PublishPreflightTests." + [Guid]::NewGuid().ToString("N"))
$passedControls = 0

function Set-LauncherExecutable {
    param([string]$Path)

    if ($IsWindows) {
        return
    }

    [IO.File]::SetUnixFileMode(
        $Path,
        [IO.UnixFileMode]::UserRead -bor `
            [IO.UnixFileMode]::UserWrite -bor `
            [IO.UnixFileMode]::UserExecute)
}

function New-FakeDotnet {
    param(
        [string]$Root,
        [string]$Version,
        [string]$CapturePath
    )

    [void](New-Item -ItemType Directory -Path $Root)
    $launcher = Join-Path $Root "dotnet.ps1"
    $source = @"
param([Parameter(ValueFromRemainingArguments = `$true)][string[]]`$Remaining)
Add-Content -LiteralPath '$($CapturePath.Replace("'", "''"))' -Value (`$Remaining -join '|')
if (`$Remaining.Count -eq 1 -and `$Remaining[0] -ceq '--version') {
    Write-Output '$Version'
    exit 0
}
if (`$Remaining.Count -eq 1 -and `$Remaining[0] -ceq '--list-sdks') {
    Write-Output '$Version [$($Root.Replace("'", "''"))/sdk]'
    exit 0
}
if (`$Remaining.Count -eq 1 -and `$Remaining[0] -ceq '--info') {
    Write-Output 'synthetic dotnet info'
    exit 0
}
if (`$Remaining.Count -eq 4 -and `$Remaining[0] -ceq 'msbuild') {
    if (`$Remaining[3] -ceq '-getProperty:NETCoreSdkVersion') {
        Write-Output '$Version'
        exit 0
    }
    if (`$Remaining[3] -ceq '-getProperty:MSBuildSDKsPath') {
        Write-Output '$($Root.Replace("'", "''"))/sdk/$Version/Sdks'
        exit 0
    }
}
Write-Error ('unexpected synthetic dotnet arguments: ' + (`$Remaining -join ' '))
exit 91
"@
    [IO.File]::WriteAllText($launcher, $source)
    Set-LauncherExecutable -Path $launcher
    return [IO.Path]::GetFullPath($launcher)
}

function New-PublishFixture {
    param(
        [string]$Name,
        [string]$PrivateVersion = "10.0.100"
    )

    $root = Join-Path $temporaryRoot $Name
    $scripts = Join-Path $root "native/windows/scripts"
    $project = Join-Path $root "native/windows/src/ScreenFix.App/ScreenFix.App.csproj"
    [void](New-Item -ItemType Directory -Path $scripts)
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $project))
    Copy-Item -LiteralPath $publishSourcePath -Destination $scripts
    Copy-Item -LiteralPath $fullAssertionSourcePath -Destination $scripts
    if (Test-Path -LiteralPath $preflightSourcePath -PathType Leaf) {
        Copy-Item -LiteralPath $preflightSourcePath -Destination $scripts
    }
    [IO.File]::WriteAllText($project, "<Project />")

    $artifacts = Join-Path $root "native/windows/artifacts/windows"
    $sentinels = @(
        (Join-Path $artifacts "release/previous.bin"),
        (Join-Path $artifacts "build/uncompressed/previous.bin"),
        (Join-Path $artifacts "build/compressed/previous.bin"),
        (Join-Path $artifacts "obj/uncompressed/previous.bin"),
        (Join-Path $artifacts "obj/compressed/previous.bin"))
    foreach ($sentinel in $sentinels) {
        [void](New-Item -ItemType Directory -Force -Path (Split-Path -Parent $sentinel))
        [IO.File]::WriteAllText($sentinel, "preserve")
    }

    $privateCapture = Join-Path $root "private-calls.txt"
    $externalCapture = Join-Path $root "external-calls.txt"
    $privateLauncher = New-FakeDotnet `
        -Root (Join-Path $root "private") `
        -Version $PrivateVersion `
        -CapturePath $privateCapture
    $externalLauncher = New-FakeDotnet `
        -Root (Join-Path $root "external") `
        -Version "10.0.400" `
        -CapturePath $externalCapture

    return [pscustomobject]@{
        PublishScript = [IO.Path]::GetFullPath((Join-Path $scripts "publish-win-x64.ps1"))
        PrivateLauncher = $privateLauncher
        ExternalLauncher = $externalLauncher
        PrivateCapture = $privateCapture
        ExternalCapture = $externalCapture
        Sentinels = $sentinels
    }
}

function Assert-NoPublishMutation {
    param(
        [object]$Fixture,
        [string]$Name
    )

    foreach ($sentinel in $Fixture.Sentinels) {
        if (-not (Test-Path -LiteralPath $sentinel -PathType Leaf) `
            -or [IO.File]::ReadAllText($sentinel) -cne "preserve") {
            throw "$Name preflight failure mutated generated output: $sentinel"
        }
    }

    foreach ($capture in @($Fixture.PrivateCapture, $Fixture.ExternalCapture)) {
        $calls = if (Test-Path -LiteralPath $capture -PathType Leaf) {
            @(Get-Content -LiteralPath $capture)
        }
        else {
            @()
        }
        $forbidden = @($calls | Where-Object {
            $_ -match '^(publish|build)(\||$)'
        })
        if ($forbidden.Count -ne 0) {
            throw "$Name preflight failure invoked a publish/build command: $($forbidden[0])"
        }
    }
}

function Invoke-ExpectedRejection {
    param(
        [object]$Fixture,
        [string]$Expected,
        [string]$Name
    )

    $diagnostic = $null
    try {
        & $Fixture.PublishScript `
            -DotnetPath $Fixture.PrivateLauncher `
            -ExternalDotnetPath $Fixture.ExternalLauncher
    }
    catch {
        $diagnostic = $_.Exception.Message
    }
    if ($diagnostic -cne $Expected) {
        throw "$Name returned an unexpected diagnostic. Expected: $Expected Actual: $diagnostic"
    }

    Assert-NoPublishMutation -Fixture $Fixture -Name $Name
    $script:passedControls++
}

try {
    [void](New-Item -ItemType Directory -Path $temporaryRoot)

    $wrongSdk = New-PublishFixture -Name "wrong-sdk" -PrivateVersion "10.0.200"
    Invoke-ExpectedRejection `
        -Fixture $wrongSdk `
        -Expected "private dotnet CLI version must be exactly 10.0.100" `
        -Name "wrong SDK"

    $reparse = New-PublishFixture -Name "reparse-ancestor"
    $privateTarget = Split-Path -Parent $reparse.PrivateLauncher
    $privateLink = Join-Path (Split-Path -Parent $privateTarget) "private-link"
    try {
        [void](New-Item `
            -ItemType SymbolicLink `
            -Path $privateLink `
            -Target $privateTarget `
            -ErrorAction Stop)
        $reparse.PrivateLauncher = Join-Path $privateLink (
            Split-Path -Leaf $reparse.PrivateLauncher)
        Invoke-ExpectedRejection `
            -Fixture $reparse `
            -Expected "private dotnet path must be an absolute regular non-reparse executable file" `
            -Name "reparse ancestor"
    }
    catch [System.UnauthorizedAccessException] {
        Write-Warning "reparse ancestor control skipped because symlink creation is unavailable"
    }
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}

Write-Output "publish preflight regressions passed ($passedControls controls)"
