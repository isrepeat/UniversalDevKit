param(
    [string]$RepositoryRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [switch]$Check,
    [switch]$PassThru
)

# Compatibility entry point; ProjectTools owns generation.
& (Join-Path $PSScriptRoot '../../Sources/Windows/ProjectTools/Generate.ps1') -ManifestPath (Join-Path $RepositoryRoot 'Components.json') -Check:$Check -PassThru:$PassThru