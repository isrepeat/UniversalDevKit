param([string]$LocalPath, [scriptblock]$ProgressCallback)

& (Join-Path $PSScriptRoot '../../GetSolutionInjector.ps1') @PSBoundParameters