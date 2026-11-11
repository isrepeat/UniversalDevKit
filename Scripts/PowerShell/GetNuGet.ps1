param([string]$LocalPath)
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
& (Join-Path $root 'Sources/Windows/UdkCli/Tools/PackageTools/Private/GetNuGet.ps1') -LocalPath $LocalPath -CacheDirectory (Join-Path $root '!tools')