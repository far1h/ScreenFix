$ErrorActionPreference = "Stop"

$dotnetPath = [IO.Path]::GetFullPath(
    (Get-Command dotnet -ErrorAction Stop).Source)
$project = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "../src/ScreenFix.App/ScreenFix.App.csproj"))
$output = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "../artifacts/windows/win-x64"))
$assertion = Join-Path $PSScriptRoot "assert-win-x64-package.ps1"

if (Test-Path -LiteralPath $output) {
    Remove-Item -LiteralPath $output -Recurse -Force
}

$publishOutput = & $dotnetPath publish $project `
    -c Release `
    -r win-x64 `
    --self-contained true `
    -o $output `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -p:EnableCompressionInSingleFile=false `
    -p:PublishTrimmed=false `
    -p:DebugType=None `
    -p:DebugSymbols=false `
    -p:UseAppHost=true

if ($LASTEXITCODE -ne 0) {
    $details = $publishOutput -join [Environment]::NewLine
    throw "dotnet publish failed with exit code $LASTEXITCODE`n$details"
}

& $assertion -OutputDirectory $output
& (Join-Path $PSScriptRoot "test-windows-native.ps1") `
    -DotnetPath $dotnetPath `
    -PublishedExecutable (Join-Path $output "ScreenFix.exe") `
    -ExpectedCompression uncompressed

$artifact = Get-Item -LiteralPath (Join-Path $output "ScreenFix.exe")
Write-Output ("{0} ({1} bytes)" -f $artifact.FullName, $artifact.Length)
