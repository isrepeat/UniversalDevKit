param(
    [string]$AndroidSdk,
    [string]$JavaHome,
    [string]$Gradle
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
. (Join-Path $root 'Scripts/PowerShell/ArtifactDirectories.ps1')
$testRoot = Reset-UdkArtifactDirectory -Root (Join-Path $root '!artifacts/tests') -Path (Join-Path $root '!artifacts/tests/AndroidKotlin.Tests')
$feed = Join-Path $testRoot 'feed'
& (Join-Path $root 'Packages/Build/Android/BuildKotlin.ps1') -Package AndroidAppKit -OutputDirectory $feed -AndroidSdk $AndroidSdk -JavaHome $JavaHome -Gradle $Gradle
. (Join-Path $root 'Scripts/Android/ResolveToolchain.ps1')
$toolchain = Resolve-UdkAndroidToolchain -AndroidSdk $AndroidSdk -JavaHome $JavaHome -Gradle $Gradle -ForConsumer -WithoutNdk
$consumer = Join-Path $testRoot 'consumer'
New-Item -ItemType Directory -Path $consumer -Force | Out-Null
Copy-Item -Path (Join-Path $root 'Tests/Fixtures/Consumers/AndroidKotlin/*') -Destination $consumer -Recurse
$savedEnvironment = @{}
foreach ($name in @('JAVA_HOME', 'ANDROID_HOME', 'ANDROID_SDK_ROOT')) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
try {
    $env:JAVA_HOME = $toolchain.JavaHome
    $env:ANDROID_HOME = $toolchain.AndroidSdk
    $env:ANDROID_SDK_ROOT = $toolchain.AndroidSdk
    & $toolchain.Gradle --project-dir $consumer --project-cache-dir "$testRoot/cache" `
        "-PudkBuildRoot=$($testRoot.Replace('\', '/'))/build" `
        "-PandroidPackagesFeedPath=$($feed.Replace('\', '/'))" assembleRelease --console=plain
    if ($LASTEXITCODE -ne 0) { throw "Independent Kotlin consumer failed with exit code $LASTEXITCODE." }
    $pom = Get-Content (Join-Path $feed 'com/isrepeat/androidappkit/1.0.19/androidappkit-1.0.19.pom') -Raw
    if ($pom -notmatch '<version>1\.0\.10</version>' -or $pom -match '<version>\+</version>') {
        throw 'AndroidAppKit must publish an exact AndroidCoreSdk dependency.'
    }
    Write-Host "Android Kotlin package delivery passed: $testRoot"
}
finally {
    foreach ($name in $savedEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process')
    }
}