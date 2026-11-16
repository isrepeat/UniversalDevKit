param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$XmlRoot,
    [string]$RegistryPath
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
. (Join-Path $PSScriptRoot 'ReadManifest.ps1')
$scope = if ($RegistryPath) { (Read-UdkManifest $RegistryPath 'ComponentRegistry').fileScope }
$manifest = Read-UdkManifest $Path $XmlRoot $scope
$manifest.PSObject.Properties.Remove('fileScope')
foreach ($project in $manifest.projects) {
    $project.PSObject.Properties.Remove('outputScope')
}
$manifest | ConvertTo-Json -Depth 100 -Compress