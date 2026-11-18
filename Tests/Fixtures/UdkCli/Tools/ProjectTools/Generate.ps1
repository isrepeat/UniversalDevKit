param([string]$ManifestPath, [switch]$Check)

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -ne 5) { throw 'The CLI must use Windows PowerShell 5.1.' }
$hash = Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256
if ($hash.Hash -notmatch '^[0-9A-F]{64}$') { throw 'Windows PowerShell could not load Get-FileHash.' }
Write-Output 'Windows PowerShell module resolution passed.'