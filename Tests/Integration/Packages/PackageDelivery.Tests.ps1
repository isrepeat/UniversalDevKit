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
if (-not $CMake -and 'WinRt' -in $Family) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    $CMake = @(& $vswhere -latest -products '*' -find 'Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe')[0]
}
$repository = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$NuGet = & (Join-Path $repository 'Scripts/PowerShell/GetNuGet.ps1') -LocalPath $NuGet
$fixtures = Join-Path $repository 'Tests/Fixtures/Packages'
. (Join-Path $repository 'Scripts/PowerShell/ArtifactDirectories.ps1')
$run = Reset-UdkArtifactDirectory -Root (Join-Path $repository '!artifacts/tests') -Path (Join-Path $repository '!artifacts/tests/PackageDelivery.Tests')
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
function TestActivationDeployment([string]$SourceDirectory, [string]$Executable, [string]$Name, [string]$ExpectedOutput) {
    foreach ($hasComponent in @($true, $false)) {
        $destination = Join-Path $run ("runtime-" + $Name + '-' + $hasComponent)
        [void][IO.Directory]::CreateDirectory($destination)
        foreach ($file in (Get-ChildItem -LiteralPath $SourceDirectory -File)) {
            if (-not $hasComponent -and $file.Name -eq 'UdkWinRtProbe.dll') { continue }
            Copy-Item -LiteralPath $file.FullName -Destination $destination
        }
        $start = [Diagnostics.ProcessStartInfo]::new()
        $start.FileName = Join-Path $destination $Executable
        $start.WorkingDirectory = $destination
        $start.UseShellExecute = $false
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        $start.EnvironmentVariables['PATH'] = [Environment]::SystemDirectory
        $process = [Diagnostics.Process]::Start($start)
        try {
            $stdout = $process.StandardOutput.ReadToEndAsync()
            $stderr = $process.StandardError.ReadToEndAsync()
            if (-not $process.WaitForExit(30000)) { $process.Kill(); throw "Activation test timeout: $Name" }
            $text = $stdout.Result + $stderr.Result
            [IO.File]::WriteAllText((Join-Path $destination 'activation.log'), $text, [Text.UTF8Encoding]::new($false))
            if ($hasComponent) {
                if ($process.ExitCode -ne 0 -or -not $text.Contains($ExpectedOutput)) { throw "Activation failed: $Name; $text" }
                Write-Host $text.TrimEnd()
            }
            else {
                if ($process.ExitCode -ne 2) { throw "Missing component must fail activation: $Name; $text" }
                Write-Host "Missing DLL activation rejected: $Name"
            }
        }
        finally { $process.Dispose() }
    }
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
        if (-not (Test-Path -LiteralPath (Join-Path $package 'winmd/UniversalDevKit.TestPackages.winmd'))) { throw 'Package WinMD is missing.' }
        $consumer = Join-Path $run 'winrt-consumer'
        CopyFixture 'WinRtConsumer' $consumer
        InvokeChecked $CMake @('-S', $consumer, '-B', (Join-Path $consumer 'build'), '-G', 'Visual Studio 18 2026', '-A', 'x64', "-DUDK_PACKAGE_ROOT=$package")
        InvokeChecked $CMake @('--build', (Join-Path $consumer 'build'), '--config', 'Release')
        TestActivationDeployment (Join-Path $consumer 'build/Release') 'consumer.exe' 'NativeDesktop' 'Native Desktop WinRT activation passed'
        InvokeChecked (Join-Path $package 'tools/win-x64/UdkHostProbe.exe') @()
        $results += [pscustomobject]@{ Family = 'NativeDesktopWinRt+HostTool'; Status = 'Passed' }
        $csConsumer = Join-Path $run 'cswinrt-consumer'
        CopyFixture 'CsWinRtConsumer' $csConsumer
        # Конфигурация восстановления генерируется только во временном окружении.
        $config = [IO.File]::ReadAllText((Join-Path $csConsumer 'NuGet.Config.in')).Replace('{{FEED}}', [Security.SecurityElement]::Escape($feed))
        [IO.File]::WriteAllText((Join-Path $csConsumer 'NuGet.Config'), $config, [Text.UTF8Encoding]::new($false))
        $csCache = Join-Path $run 'cswinrt-cache'
        $csProject = Join-Path $csConsumer 'Consumer.csproj'
        InvokeChecked 'dotnet' @('restore', $csProject, '--configfile', (Join-Path $csConsumer 'NuGet.Config'), '--packages', $csCache, '--no-cache')
        InvokeChecked 'dotnet' @('build', $csProject, '--no-restore', '-c', 'Release')
        if (-not @(Get-ChildItem (Join-Path $csConsumer 'obj/Projection') -Filter '*.cs' -Recurse).Count) { throw 'CsWinRT projection was not generated from package WinMD.' }
        $restoredCsPackage = Join-Path $csCache 'universaldevkit.testpackages.winrtcomponent/1.0.0'
        if (-not (Test-Path -LiteralPath (Join-Path $restoredCsPackage 'winmd/UniversalDevKit.TestPackages.winmd'))) { throw 'C# restore did not deliver WinMD.' }
        TestActivationDeployment (Join-Path $csConsumer 'bin/Release/net8.0-windows10.0.19041.0/win-x64') 'Consumer.exe' 'CsWinRt' 'C# CsWinRT activation passed'
        $results += [pscustomobject]@{ Family = 'CsWinRtPackageReference'; Status = 'Passed' }
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