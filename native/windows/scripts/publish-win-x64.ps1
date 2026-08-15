$ErrorActionPreference = "Stop"

$project = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "../src/ScreenFix.App/ScreenFix.App.csproj"))
$output = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "../artifacts/windows/win-x64"))
$assertion = Join-Path $PSScriptRoot "assert-win-x64-package.ps1"

if (Test-Path -LiteralPath $output) {
    Remove-Item -LiteralPath $output -Recurse -Force
}

& dotnet publish $project `
    -c Release `
    -r win-x64 `
    --self-contained true `
    -o $output `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -p:PublishTrimmed=false `
    -p:DebugType=None `
    -p:DebugSymbols=false `
    -p:UseAppHost=true

if ($LASTEXITCODE -ne 0) {
    throw "dotnet publish failed with exit code $LASTEXITCODE"
}

& $assertion -OutputDirectory $output

$artifact = Get-Item -LiteralPath (Join-Path $output "ScreenFix.exe")
Write-Output ("{0} ({1} bytes)" -f $artifact.FullName, $artifact.Length)
