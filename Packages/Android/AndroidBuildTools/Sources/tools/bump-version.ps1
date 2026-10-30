[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ProjectRoot,

# Возвращает последнюю опубликованную версию вместо следующей.
    [switch]$KeepVersion
)

$ErrorActionPreference = 'Stop'
Import-Module -Name (Join-Path $PSScriptRoot 'Modules\Module.AndroidBuildTools\Module.AndroidBuildTools.psm1') -ErrorAction Stop
Module.AndroidBuildTools\Initialize-AndroidBuildConsole
$config = Module.AndroidBuildTools\Read-AndroidBuildConfiguration $ProjectRoot
$versionFile = Join-Path $projectRoot $config.VersionFile
$distributionDirectory = Join-Path $projectRoot $config.DistributionDirectory

if (-not (Test-Path -LiteralPath $versionFile -PathType Leaf)) {
    throw "Version file not found: $versionFile"
}

$properties = ConvertFrom-StringData ([System.IO.File]::ReadAllText($versionFile))
$baseCode = 0
if (-not [int]::TryParse($properties.VERSION_CODE_BASE, [ref]$baseCode)) {
    throw 'version.properties must define integer VERSION_CODE_BASE.'
}
if ($properties.VERSION_NAME_BASE -notmatch '^\d+\.\d+$') {
    throw 'version.properties must define VERSION_NAME_BASE in major.minor format.'
}
$parts = $properties.VERSION_NAME_BASE.Split('.')
$expectedBaseCode = [long]$parts[0] * 1000000 + [long]$parts[1] * 1000
if ([long]$parts[1] -gt 999 -or $expectedBaseCode -ne $baseCode) {
    throw 'VERSION_CODE_BASE must equal major * 1000000 + minor * 1000, with minor between 0 and 999.'
}

$publishedVersions = if (Test-Path -LiteralPath $distributionDirectory -PathType Container) {
    Get-ChildItem -LiteralPath $distributionDirectory -Filter "$($config.ArtifactName)-*.apk" -File | ForEach-Object {
        $match = [regex]::Match($_.Name, "^$([regex]::Escape($config.ArtifactName))-$([regex]::Escape($properties.VERSION_NAME_BASE))\.(\d+)(?:-debug|-release)?\.apk$")
        if ($match.Success) {
            [pscustomobject]@{
                Patch = [int]$match.Groups[1].Value
            }
        }
    }
}
$latestVersion = $publishedVersions | Sort-Object Patch -Descending | Select-Object -First 1
if ($KeepVersion) {
    $patch = if ($null -eq $latestVersion) { 0 } else { $latestVersion.Patch }
} else {
    $patch = if ($null -eq $latestVersion) { 1 } else { $latestVersion.Patch + 1 }
}
$versionCode = $baseCode + $patch
if ($patch -gt 999 -or $versionCode -gt 2100000000) {
    throw 'Android version range exhausted. Increment VERSION_NAME_BASE and the corresponding VERSION_CODE_BASE.'
}
$versionName = "$($properties.VERSION_NAME_BASE).$patch"

[pscustomobject]@{
    VERSION_CODE = $versionCode
    VERSION_NAME = $versionName
}