[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$ApkUpdaterProjectRoot,
    [Parameter(Mandatory)] [string]$SigningProperties,
    [Parameter(Mandatory)] [string]$BuildToolsRoot,
    [ValidateSet('Debug', 'Release')] [string]$Configuration = 'Debug'
)

$ErrorActionPreference = 'Stop'
$updaterRoot = [IO.Path]::GetFullPath($ApkUpdaterProjectRoot)
$buildScript = Join-Path $updaterRoot 'build.ps1'
if (-not (Test-Path -LiteralPath $buildScript -PathType Leaf)) {
    throw "ApkUpdater build script was not found: $buildScript"
}
Import-Module (Join-Path $BuildToolsRoot 'tools\Modules\Module.AndroidBuildTools\Module.AndroidBuildTools.psm1')
# Расположение APK определяется конфигурацией самого Updater.
$updaterProjectConfig = Read-AndroidBuildConfiguration $updaterRoot
$variant = $Configuration.ToLowerInvariant()
$apkPath = Join-Path $updaterRoot "Build\$($updaterProjectConfig.AndroidModule)\outputs\apk\$variant\$($updaterProjectConfig.AndroidModule)-$variant.apk"
$certificateParameters = @{
    ApkPath = $apkPath
    SigningProperties = $SigningProperties
    JavaHome = Resolve-AndroidJavaHome
    AndroidSdk = Resolve-AndroidSdk
    Configuration = $Configuration
}
function Test-UpdaterCertificate {
    & (Join-Path $BuildToolsRoot 'tools\test-apk-signing.ps1') @certificateParameters
}

if (Test-UpdaterCertificate) {
    Write-Host "ApkUpdater $Configuration already uses the shared signing certificate."
    return
}
Write-Host "WARNING: ApkUpdater $Configuration APK is missing, invalid or signed with another key. Rebuilding with shared keys." -ForegroundColor Yellow
& $buildScript build-android -Configuration $Configuration -SigningProperties $SigningProperties
if (-not (Test-UpdaterCertificate)) {
    throw "Rebuilt ApkUpdater certificate does not match the shared key: $apkPath"
}
Write-Host "ApkUpdater $Configuration is ready: $apkPath. Install this APK on the device." -ForegroundColor Green