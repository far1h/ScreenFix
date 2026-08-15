$ErrorActionPreference = "Stop"

$project = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "../tests/ScreenFix.Windows.Tests/ScreenFix.Windows.Tests.csproj"))

& dotnet build $project -c Release
if ($LASTEXITCODE -ne 0) {
    throw "Windows native test build failed with exit code $LASTEXITCODE"
}

if (-not $IsWindows) {
    Write-Output "Windows native tests compiled; execution requires Windows."
    exit 0
}

& dotnet test $project -c Release --no-build
if ($LASTEXITCODE -ne 0) {
    throw "Windows native tests failed with exit code $LASTEXITCODE"
}
