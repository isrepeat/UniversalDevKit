[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ProjectRoot,

    [ValidateSet('Local', 'Drive')]
    [string]$Destination = 'Local',

    # Пересобирает APK с текущим versionCode для быстрой тестовой переустановки.
    [switch]$KeepVersion,

    # Конфигурация нативной и Android-сборки.
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release',

    [string]$TargetsConfigUrl
)

$ErrorActionPreference = 'Stop'
Import-Module -Name (Join-Path $PSScriptRoot 'Modules\Module.AndroidBuildTools\Module.AndroidBuildTools.psm1') -ErrorAction Stop
Module.AndroidBuildTools\Initialize-AndroidBuildConsole
$androidProjectConfig = Module.AndroidBuildTools\Read-AndroidBuildConfiguration $ProjectRoot
$androidProjectSharedConfig = Module.AndroidBuildTools\Read-AndroidBuildSharedConfiguration $ProjectRoot
$bumpVersion = Join-Path $PSScriptRoot 'bump-version.ps1'
$buildAndroid = Join-Path $PSScriptRoot 'build-android.ps1'
$uploadToDrive = Join-Path $PSScriptRoot 'upload-apk-to-drive.ps1'
$configurationDirectory = $Configuration.ToLowerInvariant()
$apkSuffix = if ($Configuration -eq 'Release') { 'release' } else { 'debug' }
$sourceApk = Join-Path $projectRoot "Build\$($androidProjectConfig.AndroidModule)\outputs\apk\$configurationDirectory\$($androidProjectConfig.AndroidModule)-$apkSuffix.apk"
$distributionOutput = Join-Path $projectRoot $androidProjectConfig.DistributionDirectory

$version = & $bumpVersion -ProjectRoot $ProjectRoot -KeepVersion:$KeepVersion
if ($KeepVersion) {
    Write-Host "==> Keeping Android version $($version.VERSION_CODE) / $($version.VERSION_NAME) for a test reinstall"
} else {
    Write-Host "==> Using next Android version $($version.VERSION_CODE) / $($version.VERSION_NAME)"
}
$buildParameters = @{
    ProjectRoot = $ProjectRoot
    Configuration = $Configuration
    AppVersionCode = $version.VERSION_CODE
    AppVersionName = $version.VERSION_NAME
}
if ($PSBoundParameters.ContainsKey('TargetsConfigUrl')) {
    $buildParameters.TargetsConfigUrl = $TargetsConfigUrl
}
& $buildAndroid @buildParameters

$destinationApk = Join-Path $distributionOutput "$($androidProjectConfig.ArtifactName)-$($version.VERSION_NAME)-$apkSuffix.apk"
New-Item -ItemType Directory -Path $distributionOutput -Force | Out-Null
Copy-Item -LiteralPath $sourceApk -Destination $destinationApk -Force
Write-Host "Distribution APK ready: $destinationApk"

if ($Destination -eq 'Drive') {
    Write-Host "==> Uploading $($androidProjectConfig.ArtifactName) APK to Google Drive"
    # Имя содержит версию, поэтому Google Drive хранит историю релизов.
    & $uploadToDrive -ApkPath $destinationApk -OAuthClientPath $androidProjectSharedConfig.Paths.DriveOAuthClientPath -TokenPath $androidProjectSharedConfig.Paths.DriveTokenPath -DrivePath $androidProjectConfig.Drive.Path
    Write-Host "APK uploaded to Google Drive: $destinationApk"
}