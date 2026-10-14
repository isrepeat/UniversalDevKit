param(
    [ValidateSet('Managed', 'BuildTools', 'Templates', 'AndroidNative', 'AndroidMaven', 'NativeWindows', 'WinRt')]
    [string[]]$Family = @('Managed', 'BuildTools', 'Templates'),
    [string]$NuGet = 'nuget.exe',
    [string]$CMake,
    [string]$AndroidNdk,
    [string]$Gradle,
    [string]$GradleCache,
    [string]$JavaHome,
    [string]$AndroidSdk,
    [ValidateSet('arm64-v8a', 'armeabi-v7a', 'x86_64')][string]$AndroidAbi = 'arm64-v8a'
)
$env:DOTNET_CLI_UI_LANGUAGE = 'en-US'
$env:VSLANG = '1033'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)

$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$fixtures = Join-Path $repository 'Tests/Fixtures/Packages'
$run = Join-Path $repository ('!artifacts/tests/delivery-' + [Guid]::NewGuid().ToString('N').Substring(0, 12))
$feed = Join-Path $run 'feed'
$cache = Join-Path $run 'cache'
[void][IO.Directory]::CreateDirectory($feed)
function InvokeChecked([string]$Tool, [string[]]$Arguments) {
    & $Tool @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "$Tool failed: $LASTEXITCODE" }
}
function CopyFixture([string]$Name, [string]$Destination) {
    [void][IO.Directory]::CreateDirectory($Destination)
    Copy-Item -Path (Join-Path $fixtures "$Name/*") -Destination $Destination -Recurse
}
# Сохраняем окружение для диагностики; test-feed не затрагивает пользовательские feeds.
$oldJava = $env:JAVA_HOME
$oldSdk = $env:ANDROID_HOME
$oldGradle = $env:GRADLE_USER_HOME
$results = @()
try {
    $nugetFamilies = @($Family | Where-Object { $_ -in @('Managed', 'BuildTools', 'Templates', 'AndroidNative', 'WinRt') })
    # Managed и BuildTools проверяются вместе реальным consumer.
    if ('Managed' -in $nugetFamilies -or 'BuildTools' -in $nugetFamilies) {
        $nugetFamilies = @(@($nugetFamilies) + @('Managed', 'BuildTools') | Select-Object -Unique)
    }
    if ($nugetFamilies.Count) {
        & (Join-Path $repository 'Tests/Infrastructure/BuildTestPackages.ps1') -Family $nugetFamilies -OutputDirectory $feed -NuGet $NuGet -CMake $CMake -AndroidNdk $AndroidNdk -AndroidAbi $AndroidAbi
    }
    if ('Managed' -in $nugetFamilies) {
        $consumer = Join-Path $run 'managed-consumer'
        CopyFixture 'Consumer' $consumer
        InvokeChecked 'dotnet' @('restore', (Join-Path $consumer 'Consumer.csproj'), '--source', $feed, '--packages', $cache, '--no-cache')
        InvokeChecked 'dotnet' @('build', (Join-Path $consumer 'Consumer.csproj'), '--no-restore', '-c', 'Release')
        InvokeChecked 'dotnet' @('exec', '--roll-forward', 'Major', (Join-Path $consumer 'bin/Release/net8.0/Consumer.dll'))
        $results += [pscustomobject]@{ Family = 'Managed+BuildTools'; Status = 'Passed' }
    }
    if ('Templates' -in $Family) {
        InvokeChecked $NuGet @('install', 'UniversalDevKit.TestPackages.ProjectTemplates', '-Version', '1.0.0', '-Source', $feed, '-OutputDirectory', $cache, '-NoCache', '-DirectDownload', '-NonInteractive', '-ForceEnglishOutput')
        $consumer = Join-Path $run 'template-consumer'
        & (Join-Path $cache 'UniversalDevKit.TestPackages.ProjectTemplates.1.0.0/tools/NewProject.ps1') -Destination $consumer
        InvokeChecked 'dotnet' @('restore', (Join-Path $consumer 'Template.csproj'), '--source', $feed, '--packages', $cache, '--no-cache')
        InvokeChecked 'dotnet' @('build', (Join-Path $consumer 'Template.csproj'), '--no-restore', '-c', 'Release')
        InvokeChecked 'dotnet' @('exec', '--roll-forward', 'Major', (Join-Path $consumer 'bin/Release/net8.0/Template.dll'))
        $results += [pscustomobject]@{ Family = 'Templates'; Status = 'Passed' }
    }
    if ('WinRt' -in $Family) {
        InvokeChecked $NuGet @('install', 'UniversalDevKit.TestPackages.WinRtComponent', '-Version', '1.0.0', '-Source', $feed, '-OutputDirectory', $cache, '-NoCache', '-DirectDownload', '-NonInteractive', '-ForceEnglishOutput')
        $package = Join-Path $cache 'UniversalDevKit.TestPackages.WinRtComponent.1.0.0'
        $consumer = Join-Path $run 'winrt-consumer'
        CopyFixture 'WinRtConsumer' $consumer
        InvokeChecked $CMake @('-S', $consumer, '-B', (Join-Path $consumer 'build'), '-G', 'Visual Studio 18 2026', '-A', 'x64', "-DUDK_PACKAGE_ROOT=$package")
        InvokeChecked $CMake @('--build', (Join-Path $consumer 'build'), '--config', 'Release')
        InvokeChecked (Join-Path $consumer 'build/Release/consumer.exe') @()
        InvokeChecked (Join-Path $package 'tools/win-x64/UdkHostProbe.exe') @()
        $results += [pscustomobject]@{ Family = 'WinRt+HostTool'; Status = 'Passed' }
    }
    if ('AndroidNative' -in $Family) {
        InvokeChecked $NuGet @('install', 'UniversalDevKit.TestPackages.AndroidNativeLibrary', '-Version', '1.0.0', '-Source', $feed, '-OutputDirectory', $cache, '-NoCache', '-DirectDownload', '-NonInteractive', '-ForceEnglishOutput')
        $consumer = Join-Path $run 'android-native-consumer'
        CopyFixture 'AndroidNativeConsumer' $consumer
        InvokeChecked $CMake @('-S', $consumer, '-B', (Join-Path $consumer 'build'), '-G', 'Ninja', "-DCMAKE_TOOLCHAIN_FILE=$AndroidNdk/build/cmake/android.toolchain.cmake", "-DANDROID_ABI=$AndroidAbi", '-DANDROID_PLATFORM=android-24', '-DANDROID_STL=c++_shared', '-DCMAKE_BUILD_TYPE=Release', "-DUDK_PACKAGE_ROOT=$cache/UniversalDevKit.TestPackages.AndroidNativeLibrary.1.0.0")
        InvokeChecked $CMake @('--build', (Join-Path $consumer 'build'))
        $results += [pscustomobject]@{ Family = 'AndroidNative'; Status = 'BuildPassed;DeviceRunNotPerformed' }
    }
    if ('AndroidMaven' -in $Family) {
        if (-not $Gradle -or -not $JavaHome -or -not $AndroidSdk) { throw 'AndroidMaven requires Gradle (8.11.1), JavaHome (JDK 17 or 21) and AndroidSdk (API 36).' }
        $env:JAVA_HOME = $JavaHome
        $env:ANDROID_HOME = $AndroidSdk
        $env:GRADLE_USER_HOME = if ($GradleCache) { [IO.Path]::GetFullPath($GradleCache) } else { Join-Path $run 'gradle-cache' }
        $maven = Join-Path $run 'maven'
        $producer = Join-Path $run 'android-producer'
        CopyFixture 'AndroidMaven' $producer
        InvokeChecked $Gradle @('-p', $producer, '--no-daemon', "-PtestPackagesFeed=$maven", ':core:publishReleasePublicationToPackageDeliveryRepository')
        InvokeChecked $Gradle @('-p', $producer, '--no-daemon', "-PtestPackagesFeed=$maven", ':appkit:publishReleasePublicationToPackageDeliveryRepository')
        $consumer = Join-Path $run 'android-maven-consumer'
        [void][IO.Directory]::CreateDirectory($consumer)
        foreach ($file in @('settings.gradle.kts', 'build.gradle.kts', 'gradle.properties', 'consumer')) {
            Copy-Item -LiteralPath (Join-Path $producer $file) -Destination $consumer -Recurse
        }
        InvokeChecked $Gradle @('-p', $consumer, '--no-daemon', "-PtestPackagesFeed=$maven", '-PconsumerOnly=true', ':consumer:assembleDebug')
        foreach ($artifact in @('core', 'appkit')) {
            $prefix = Join-Path $maven "org/universaldevkit/packagedelivery/$artifact/1.0.0/$artifact-1.0.0"
            foreach ($extension in @('.aar', '.pom', '-sources.jar')) {
                if (-not (Test-Path -LiteralPath ($prefix + $extension))) { throw "Missing Maven artifact: $prefix$extension" }
            }
        }
        $results += [pscustomobject]@{ Family = 'AndroidMaven'; Status = 'BuildPassed;DeviceRunNotPerformed' }
    }
    if ('NativeWindows' -in $Family) {
        & (Join-Path $PSScriptRoot 'NuGet.Tests.ps1') -LicenseFile (Join-Path $repository 'LICENSE') -NuGet $NuGet -CMake $CMake
        $results += [pscustomobject]@{ Family = 'NativeWindows'; Status = 'Passed' }
    }
}
catch {
    $results += [pscustomobject]@{ Family = 'Run'; Status = 'Failed: ' + $_.Exception.Message }
    throw
}
finally {
    $env:JAVA_HOME = $oldJava
    $env:ANDROID_HOME = $oldSdk
    $env:GRADLE_USER_HOME = $oldGradle
    $results | Export-Csv -LiteralPath (Join-Path $run 'summary.csv') -NoTypeInformation -Encoding UTF8
    Write-Host "Preserved test workspace: $run"
}