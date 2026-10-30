param()

$ErrorActionPreference = 'Stop'
$env:DOTNET_CLI_UI_LANGUAGE = 'en-US'
$env:VSLANG = '1033'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)

Write-Host 'Preparing SolutionInjector...'
$solutionInjector = & (Join-Path $PSScriptRoot 'GetSolutionInjector.ps1')
Write-Host "Ready: $solutionInjector"
Write-Host 'Preparing NuGet...'
$nuget = & (Join-Path $PSScriptRoot 'GetNuGet.ps1')
Write-Host "Ready: $nuget"
Write-Host 'Repository tools are ready.'