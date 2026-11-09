[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ProjectRoot,

    # Заново конфигурирует CMake перед компиляцией нативной библиотеки.
    [switch]$Clean,

    # Собирает только нативную библиотеку.
    [switch]$NativeOnly,

    # Конфигурация нативной и Android-сборки.
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Debug',

    # Проект поддерживает только физические устройства ARM64.
    [ValidateSet('arm64-v8a')]
    [string]$Architecture = 'arm64-v8a',

    # Версия передаётся build-and-distribute.ps1 и не записывается в Git-файлы.
    [int]$AppVersionCode,

    [string]$AppVersionName,

    [string]$SigningProperties,

    [string]$TargetsConfigUrl
)

$ErrorActionPreference = 'Stop'
Import-Module -Name (Join-Path $PSScriptRoot 'Modules\Module.AndroidBuildTools\Module.AndroidBuildTools.psm1') -ErrorAction Stop
Module.AndroidBuildTools\Initialize-AndroidBuildConsole
$androidProjectConfig = Module.AndroidBuildTools\Read-AndroidBuildConfiguration $ProjectRoot
$androidProjectSharedConfig = Module.AndroidBuildTools\Read-AndroidBuildSharedConfiguration $ProjectRoot
$gradleRoot = Join-Path $projectRoot $androidProjectConfig.GradleRoot
$gradleWrapper = Join-Path $gradleRoot 'gradlew.bat'
$configurationDirectory = $Configuration.ToLowerInvariant()
$apkSuffix = if ($Configuration -eq 'Release') { 'release' } else { 'debug' }
$apkPath = Join-Path $projectRoot "Build\$($androidProjectConfig.AndroidModule)\outputs\apk\$configurationDirectory\$($androidProjectConfig.AndroidModule)-$apkSuffix.apk"

function Invoke-Checked {
    param(
        [Parameter(Mandatory)] [string]$Program,
        [Parameter(Mandatory)] [string[]]$Arguments
    )

    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code ${LASTEXITCODE}: $Program $($Arguments -join ' ')"
    }
}

# Нативные инструменты нужны только проектам с CMake.
$usesPrefab = $androidProjectConfig.Native -and $androidProjectConfig.Native.Prefab
$hasNativeBuild = $null -ne $androidProjectConfig.Native -or -not [string]::IsNullOrWhiteSpace($androidProjectConfig.NativeLibrary)
if ($NativeOnly -and -not $hasNativeBuild) {
    throw 'NativeOnly is not supported by a project without Native configuration.'
}
if ($hasNativeBuild -and -not $usesPrefab) {
    foreach ($name in @('AndroidHost', 'NativeLibrary', 'AndroidPresetPrefix', 'CMakeVersionVariable')) {
        if ([string]::IsNullOrWhiteSpace($androidProjectConfig[$name])) {
            throw "Native Android project must define $name."
        }
    }
    $tools = Module.AndroidBuildTools\Resolve-AndroidBuildTools
    $cmake = $tools.CMake
}
if (-not $PSBoundParameters.ContainsKey('SigningProperties')) {
    $SigningProperties = $androidProjectSharedConfig.Paths.SigningProperties
}
$javaHome = Module.AndroidBuildTools\Resolve-AndroidJavaHome
$androidSdk = Module.AndroidBuildTools\Resolve-AndroidSdk
if ($usesPrefab) {
    . (Join-Path $PSScriptRoot 'Android/ResolveToolchain.ps1')
    $udkToolchain = Resolve-UdkAndroidToolchain -ForConsumer -Gradle $gradleWrapper
    $javaHome = $udkToolchain.JavaHome
    $androidSdk = $udkToolchain.AndroidSdk
    $env:ANDROID_NDK_HOME = $udkToolchain.AndroidNdk
}
$env:JAVA_HOME = $javaHome
$env:ANDROID_HOME = $androidSdk
$env:ANDROID_SDK_ROOT = $androidSdk
$env:Path = "$(Join-Path $javaHome 'bin');$env:Path"

if ($PSBoundParameters.ContainsKey('AppVersionCode') -xor $PSBoundParameters.ContainsKey('AppVersionName')) {
    throw 'AppVersionCode and AppVersionName must be specified together.'
}
# Передаём версию явно, чтобы CMake не сохранил номер предыдущей distribution-сборки.
if (-not $PSBoundParameters.ContainsKey('AppVersionName')) {
    $baseVersion = ConvertFrom-StringData ([System.IO.File]::ReadAllText((Join-Path $ProjectRoot $androidProjectConfig.VersionFile)))
    $AppVersionCode = [int]$baseVersion.VERSION_CODE_BASE
    $AppVersionName = "$($baseVersion.VERSION_NAME_BASE).0"
}
if ($hasNativeBuild -and -not $usesPrefab) {
    $cmakeConfigureArguments = @('--preset', "$($androidProjectConfig.AndroidPresetPrefix)-$configurationDirectory", "-DCMAKE_MAKE_PROGRAM=$($tools.Ninja)")
    $cmakeConfigureArguments += "-D$($androidProjectConfig.CMakeVersionVariable)=$AppVersionName"
    $cmakeConfigureArguments += "-DANDROID_PACKAGES_FEED=$($androidProjectSharedConfig.Paths.PackagesFeed)"
}

if ($hasNativeBuild -and -not $usesPrefab) {
    & (Join-Path $PSScriptRoot 'generate-xaml.ps1') -ProjectRoot $ProjectRoot

    Push-Location $projectRoot
    try {
        $cmakePreset = "$($androidProjectConfig.AndroidPresetPrefix)-$configurationDirectory"
        Write-Host "==> Building native $Architecture $Configuration library with CMake"
        if ($Clean) {
            Invoke-Checked $cmake (@('--fresh') + $cmakeConfigureArguments)
        } else {
            Invoke-Checked $cmake $cmakeConfigureArguments
        }
        Invoke-Checked $cmake @('--build', '--preset', $cmakePreset)
    } finally {
        Pop-Location
    }

    $nativeLibrary = Join-Path $projectRoot "Build\$($androidProjectConfig.AndroidHost)\android\jniLibs\$Architecture\$($androidProjectConfig.NativeLibrary)"
    if (-not (Test-Path $nativeLibrary)) {
        throw "CMake completed but did not produce $nativeLibrary"
    }

    if ($NativeOnly) {
        Write-Host "Native library ready: $nativeLibrary"
        return
    }
}

if ($usesPrefab) {
    $tools = Module.AndroidBuildTools\Resolve-AndroidBuildTools
    $cmakeVersion = (& $tools.CMake --version | Select-Object -First 1) -replace '^cmake version ', ''
    $cmakeRoot = Join-Path $ProjectRoot "Build/Tools/CMake-$cmakeVersion"
    if (-not (Test-Path (Join-Path $cmakeRoot 'bin/cmake.exe'))) {
        [void][IO.Directory]::CreateDirectory((Split-Path $cmakeRoot))
        Copy-Item -LiteralPath (Split-Path (Split-Path $tools.CMake)) -Destination $cmakeRoot -Recurse
    }
    Copy-Item -LiteralPath $tools.Ninja -Destination (Join-Path $cmakeRoot 'bin/ninja.exe') -Force
    $localProperties = 'sdk.dir=' + $androidSdk.Replace('\', '/') + "`ncmake.dir=" + $cmakeRoot.Replace('\', '/')
    [IO.File]::WriteAllText((Join-Path $gradleRoot 'local.properties'), $localProperties, [Text.UTF8Encoding]::new($false))
    & (Join-Path $PSScriptRoot 'generate-xaml.ps1') -ProjectRoot $ProjectRoot
}
# Kotlin-проект собирается только Gradle; нативный проект дополнительно упаковывает библиотеку CMake.
$gradleTasks = @(
    ":$($androidProjectConfig.AndroidModule):assemble$Configuration"
)
$gradleArguments = @('--no-daemon', "-PappVersionCode=$AppVersionCode", "-PappVersionName=$AppVersionName")
$gradleArguments += "-PappVersionFile=$($androidProjectConfig.VersionFile)"
if ($SigningProperties) {
    $gradleArguments += "-PandroidSigningProperties=$SigningProperties"
}
if ($NativeOnly -and $usesPrefab) { $gradleTasks = @('externalNativeBuild' + $Configuration) }
if ($Clean) {
    $gradleTasks = @(":$($androidProjectConfig.AndroidModule):clean") + $gradleTasks
}
$previousTargetsConfigUrl = $env:TARGETS_CONFIG_URL
if ($PSBoundParameters.ContainsKey('TargetsConfigUrl')) {
    $env:TARGETS_CONFIG_URL = $TargetsConfigUrl
}
Write-Host "==> Running Gradle tasks: $($gradleTasks -join ', ')"
Write-Host "==> Using Java: $javaHome"
Write-Host "==> Using Android SDK: $androidSdk"
# Gradle определяет Android-проект по текущему каталогу. Launcher и settings
# находятся в Tools/Gradle, поэтому Gradle запускается оттуда.
Push-Location $gradleRoot
try {
    Invoke-Checked $gradleWrapper ($gradleArguments + $gradleTasks)
} finally {
    $env:TARGETS_CONFIG_URL = $previousTargetsConfigUrl
    Pop-Location
}

if ($NativeOnly -and $usesPrefab) { Write-Host 'Native Prefab build completed.'; return }
if (-not (Test-Path $apkPath)) {
    throw "Gradle completed but did not produce $apkPath"
}
Write-Host "APK ready: $apkPath"