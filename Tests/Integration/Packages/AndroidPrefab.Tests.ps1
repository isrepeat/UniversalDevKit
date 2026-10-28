param(
    [string]$AndroidSdk,
    [string]$AndroidNdk,
    [string]$Gradle,
    [string]$JavaHome,
    [string]$CMake,
    [string]$Ninja,
    [string]$Feed,
    [string]$Serial,
    [ValidateSet('arm64-v8a', 'x86_64')][string]$Abi = 'arm64-v8a',
    [string[]]$Components = @('Helpers', 'HeleprsTest', 'DiagnosticTest'),
    [ValidateSet('Static', 'Dynamic')][string[]]$Mode = @('Static', 'Dynamic'),
    [switch]$SkipDevice
)
$env:DOTNET_CLI_UI_LANGUAGE = 'en-US'
$env:VSLANG = '1033'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)
$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
. (Join-Path $repository 'Scripts/Android/ResolveToolchain.ps1')
$tools = Resolve-UdkAndroidToolchain -AndroidNdk $AndroidNdk -AndroidSdk $AndroidSdk -JavaHome $JavaHome -Gradle $Gradle -ForConsumer
$AndroidNdk = $tools.AndroidNdk
$AndroidSdk = $tools.AndroidSdk
$JavaHome = $tools.JavaHome
$Gradle = $tools.Gradle
$run = Join-Path $repository ('!artifacts/Android/tests/' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
[void][IO.Directory]::CreateDirectory($run)
$oldJava = $env:JAVA_HOME
$oldSdk = $env:ANDROID_HOME
$results = @()
function RunTool([string]$Tool, [string[]]$Arguments, [string]$Log, [string]$ExpectedError = '') {
    $previous = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & $Tool @Arguments 2>&1 | Out-String
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previous }
    [IO.File]::WriteAllText($Log, $output, [Text.UTF8Encoding]::new($false))
    if ($ExpectedError) {
        if ($code -eq 0 -or $output -notmatch $ExpectedError) { throw "Expected rejection: $ExpectedError; see $Log; $output" }
    } elseif ($code -ne 0) { throw "Tool failed: $Tool; see $Log; $output" }
    return $output
}
try {
    $env:JAVA_HOME = $JavaHome
    $env:ANDROID_HOME = $AndroidSdk
    if (-not $CMake) {
        $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
        $CMake = @(& $vswhere -latest -products '*' -find 'Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe')[0]
    }
    if (-not $Ninja) { $Ninja = Join-Path (Split-Path (Split-Path (Split-Path $CMake -Parent) -Parent) -Parent) 'Ninja/ninja.exe' }
    if (-not $Feed) {
        $Feed = Join-Path $run 'feed'
        & (Join-Path $repository 'Packages/Build/Android/Build.ps1') -AndroidNdk $AndroidNdk -CMake $CMake -Ninja $Ninja -Abi $Abi -Components $Components -OutputDirectory $Feed | Out-Host
    }
    $Feed = (Resolve-Path -LiteralPath $Feed).Path
    $version = (Get-Content (Join-Path $repository 'Version.json') -Raw | ConvertFrom-Json).version
    $ndkVersion = ((Get-Content (Join-Path $AndroidNdk 'source.properties') | Where-Object { $_ -match '^Pkg.Revision\s*=' }) -split '=')[1].Trim()
    # Provide standalone CMake/Ninja to Gradle without modifying the SDK installation.
    $cmakeRoot = Join-Path $run 'cmake'
    Copy-Item -LiteralPath (Split-Path (Split-Path $CMake -Parent) -Parent) -Destination $cmakeRoot -Recurse
    Copy-Item -LiteralPath $Ninja -Destination (Join-Path $cmakeRoot 'bin/ninja.exe')
    $adb = Join-Path $AndroidSdk 'platform-tools/adb.exe'
    if (-not $SkipDevice) {
        if (-not $Serial) { throw 'Pass -Serial for an authorized device/emulator, or -SkipDevice for build-only validation.' }
        $deviceAbi = (RunTool $adb @('-s', $Serial, 'shell', 'getprop', 'ro.product.cpu.abilist') (Join-Path $run 'device-abi.log')).Trim()
        if ($Abi -notin $deviceAbi.Split(',')) { throw "Device does not support $Abi" }
    }
    foreach ($component in $Components) {
        $registry = Get-Content (Join-Path $repository "Projects/Components/$component.json") -Raw | ConvertFrom-Json
        $componentModes = if ($registry.kind -eq 'headerOnly') { @('Shared') } else { $Mode }
        foreach ($linkage in $componentModes) {
            $name = "$component-$linkage"
            if ($registry.kind -eq 'headerOnly') {
                $aarPath = Join-Path $Feed "org/universaldevkit/universaldevkit-$($component.ToLowerInvariant())-shared-release/$version/universaldevkit-$($component.ToLowerInvariant())-shared-release-$version.aar"
                Add-Type -AssemblyName System.IO.Compression.FileSystem
                $archive = [IO.Compression.ZipFile]::OpenRead($aarPath)
                try {
                    if (@($archive.Entries | Where-Object { $_.FullName -match '/libs/|\.(a|so)$' }).Count) { throw 'Header-only AAR contains binaries.' }
                    foreach ($header in $registry.headers) {
                        $publicPath = '/include/' + ($header -replace ('^Includes/' + $component + '/'), '')
                        if (-not @($archive.Entries | Where-Object { $_.FullName.EndsWith($publicPath) }).Count) { throw "Header-only AAR is missing public header: $header" }
                    }
                } finally { $archive.Dispose() }
            }
            $consumer = Join-Path $run $name
            Copy-Item -LiteralPath (Join-Path $repository 'Tests/Fixtures/Consumers/AndroidPrefab') -Destination $consumer -Recurse
            $properties = 'sdk.dir=' + $AndroidSdk.Replace('\', '/') + "`ncmake.dir=" + $cmakeRoot.Replace('\', '/')
            [IO.File]::WriteAllText((Join-Path $consumer 'local.properties'), $properties, [Text.UTF8Encoding]::new($false))
            $arguments = @('-p', $consumer, '--no-daemon', "-PudkFeed=$Feed", "-PudkNdk=$AndroidNdk", "-PudkNdkVersion=$ndkVersion", "-PudkVersion=$version", "-PudkComponent=$component", "-PudkMode=$linkage", "-PudkAbi=$Abi", ':app:assembleRelease')
            [void](RunTool $Gradle $arguments (Join-Path $run "$name-build.log"))
            $apk = Join-Path $consumer 'app/build/outputs/apk/release/app-release.apk'
            if (-not (Test-Path -LiteralPath $apk)) { throw 'Consumer APK was not created.' }
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $zip = [IO.Compression.ZipFile]::OpenRead($apk)
            try {
                $libraries = @($zip.Entries.FullName | Where-Object { $_ -match "^lib/$Abi/.*\.so$" } | ForEach-Object { ($_ -split '/')[-1] } | Sort-Object)
                $expected = @('libc++_shared.so', 'libudk_android_consumer.so')
                if ($linkage -eq 'Dynamic') { $expected += 'libuniversaldevkit_' + $component.ToLowerInvariant() + '_dynamic.so' }
                if (Compare-Object @($expected | Sort-Object) $libraries) { throw "Unexpected APK runtime libraries: $libraries" }
            } finally { $zip.Dispose() }
            $status = 'BuildPassed-DeviceNotRun'
            if (-not $SkipDevice) {
                [void](RunTool $adb @('-s', $Serial, 'install', '-r', $apk) (Join-Path $run "$name-install.log"))
                $testOutput = RunTool $adb @('-s', $Serial, 'shell', 'am', 'instrument', '-w', 'org.universaldevkit.packageconsumer/.PackageInstrumentation') (Join-Path $run "$name-run.log")
                if ($testOutput -notmatch 'UDK_RESULT=PASS') { throw "Android runtime test failed: $testOutput" }
                $status = 'Passed'
            }
            $results += [pscustomobject]@{ Component = $component; Linkage = $linkage; Abi = $Abi; Status = $status }
            if ($component -eq 'DiagnosticTest' -and $linkage -eq 'Dynamic') {
                [void](RunTool $Gradle ($arguments + '-PudkStl=c++_static') (Join-Path $run 'wrong-stl.log') 'UDK requires c\+\+_shared|static STL|STL.*incompatib|No compatible librar')
                [void](RunTool $Gradle ($arguments + '-PudkConflict=ON') (Join-Path $run 'conflicting-variants.log') 'Conflicting UDK Android variant')
            }
            Write-Host "$name : $status"
        }
    }
} catch {
    $results += [pscustomobject]@{ Component = ''; Linkage = ''; Abi = $Abi; Status = 'Failed: ' + $_.Exception.Message }
    throw
} finally {
    $env:JAVA_HOME = $oldJava
    $env:ANDROID_HOME = $oldSdk
    $results | Export-Csv -LiteralPath (Join-Path $run 'summary.csv') -NoTypeInformation -Encoding UTF8
    Write-Host "Android package test report: $run"
}