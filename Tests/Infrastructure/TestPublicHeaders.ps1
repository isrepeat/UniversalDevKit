param([string]$RepositoryPath = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)), [string]$CMake = 'cmake')

$env:DOTNET_CLI_UI_LANGUAGE = 'en-US'
$env:VSLANG = '1033'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)

$ErrorActionPreference = 'Stop'
if (-not (Get-Command $CMake -ErrorAction SilentlyContinue)) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    $installation = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    $CMake = Join-Path $installation 'Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe'
}
$build = Join-Path $RepositoryPath ('!artifacts/tests/PublicHeaders-' + [Guid]::NewGuid().ToString('N'))
$source = Join-Path $PSScriptRoot '../Integration/Cmake/PublicHeaders'
& $CMake -S $source -B $build -G 'Visual Studio 18 2026' -A x64 "-DUDK_REPOSITORY=$RepositoryPath"
if ($LASTEXITCODE -ne 0) { throw 'Public header configuration failed.' }
foreach ($configuration in @('Debug', 'Release')) {
    & $CMake --build $build --config $configuration
    if ($LASTEXITCODE -ne 0) { throw "Public header compilation failed: $configuration" }
}
Write-Host 'PASS: public headers compile independently, Debug/Release x64.'