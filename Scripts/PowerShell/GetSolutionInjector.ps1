param([string]$LocalPath, [scriptblock]$ProgressCallback)

& (Join-Path $PSScriptRoot '../../Sources/Windows/UdkCli/Tools/GetSolutionInjector.ps1') @PSBoundParameters