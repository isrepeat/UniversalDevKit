param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$XmlRoot
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
. (Join-Path $PSScriptRoot 'ReadManifest.ps1')
Read-UdkManifest $Path $XmlRoot | ConvertTo-Json -Depth 100 -Compress