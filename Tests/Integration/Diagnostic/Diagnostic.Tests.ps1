#requires -Version 7.0
param(
    [ValidateSet('Windows', 'Android')][string]$Platform = 'Windows',
    [ValidateSet('Debug', 'Release')][string[]]$Configuration = @('Debug', 'Release'),
    [string]$CMake,
    [string]$Ninja,
    [string]$AndroidNdk,
    [string]$AndroidSdk,
    [ValidateSet('arm64-v8a', 'x86_64')][string]$Abi = 'arm64-v8a',
    [string]$Serial,
    [switch]$SkipDevice
)

$ErrorActionPreference = 'Stop'
$env:DOTNET_CLI_UI_LANGUAGE = 'en-US'
$env:VSLANG = '1033'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)
$repository = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
. (Join-Path $repository 'Scripts/PowerShell/ArtifactDirectories.ps1')
$run = Reset-UdkArtifactDirectory -Root (Join-Path $repository '!artifacts/tests') -Path (Join-Path $repository '!artifacts/tests/Diagnostic.Tests')
[void][IO.Directory]::CreateDirectory($run)
$records = @(foreach ($config in ($Configuration | Select-Object -Unique)) {
    foreach ($scenario in @('contract', 'threads', 'modules')) {
        [pscustomobject]@{ Platform = $Platform; Configuration = $config; Scenario = $scenario; Build = 'NotRun'; Execution = 'NotRun'; Log = ''; Details = '' }
    }
})

function Save-Report {
    $records | Export-Csv (Join-Path $run 'summary.csv') -NoTypeInformation -Encoding UTF8
}

function Invoke-Tool([string]$Tool, [string[]]$ToolArguments, [string]$Log, [int]$TimeoutSeconds = 240) {
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $Tool
    $startInfo.WorkingDirectory = $repository
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $ToolArguments) { [void]$startInfo.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.Kill($true)
            $process.WaitForExit()
            [IO.File]::WriteAllText($Log, $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult())
            throw "Tool timed out after ${TimeoutSeconds}s: $Tool"
        }
        $output = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()
        [IO.File]::WriteAllText($Log, $output)
        if ($process.ExitCode -ne 0) { throw "Tool failed ($($process.ExitCode)): $Tool. See $Log" }
        return $output
    }
    finally { $process.Dispose() }
}

$failed = $false
try {
    if ($Platform -eq 'Windows' -and $SkipDevice) { throw '-SkipDevice applies only to Android.' }
    if (-not $CMake) {
        $command = Get-Command cmake.exe -ErrorAction SilentlyContinue
        if ($command) { $CMake = $command.Source }
        else {
            $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
            $CMake = @(& $vswhere -latest -products '*' -find 'Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe' | Select-Object -First 1)[0]
        }
    }
    $CMake = (Resolve-Path -LiteralPath $CMake).Path
    $fixture = Join-Path $repository 'Tests/Fixtures/Consumers/Diagnostic'
    if ($Platform -eq 'Android') {
        . (Join-Path $repository 'Scripts/Android/ResolveToolchain.ps1')
        $toolchain = Resolve-UdkAndroidToolchain -AndroidNdk $AndroidNdk
        $AndroidNdk = $toolchain.AndroidNdk
        if (-not $Ninja) {
            $command = Get-Command ninja.exe -ErrorAction SilentlyContinue
            if ($command) { $Ninja = $command.Source }
            else { $Ninja = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $CMake))) 'Ninja/ninja.exe' }
        }
        $Ninja = (Resolve-Path -LiteralPath $Ninja).Path
    }

    foreach ($config in ($Configuration | Select-Object -Unique)) {
        $current = @($records | Where-Object Configuration -eq $config)
        $build = Join-Path $run "build-$config"
        $configureArguments = @('-S', $fixture, '-B', $build)
        if ($Platform -eq 'Windows') {
            $configureArguments += @('-G', 'Visual Studio 18 2026', '-A', 'x64')
        }
        else {
            # CMake can use an 8.3 clang++ executable path on Windows; preserve C++ driver mode at link time.
            $configureArguments += @('-G', 'Ninja', "-DCMAKE_MAKE_PROGRAM=$Ninja", "-DCMAKE_BUILD_TYPE=$config",
                "-DCMAKE_TOOLCHAIN_FILE=$AndroidNdk/build/cmake/android.toolchain.cmake", "-DANDROID_ABI=$Abi",
                '-DANDROID_PLATFORM=android-26', '-DANDROID_STL=c++_shared', '-DCMAKE_CXX_FLAGS=--driver-mode=g++')
        }
        try {
            [void](Invoke-Tool $CMake $configureArguments (Join-Path $run "$config-configure.log"))
            [void](Invoke-Tool $CMake @('--build', $build, '--config', $config, '--parallel', '4') (Join-Path $run "$config-build.log") 600)
        }
        catch {
            $current | ForEach-Object { $_.Build = 'Failed' }
            throw
        }
        $current | ForEach-Object { $_.Build = 'Passed' }
        Save-Report
        $bin = Join-Path $build "bin/$config"
        if ($Platform -eq 'Android' -and $SkipDevice) {
            $current | ForEach-Object { $_.Execution = 'DeviceNotRun'; $_.Details = 'Explicit -SkipDevice: build only is not runtime verification.' }
            Save-Report
            continue
        }

        if ($Platform -eq 'Android') {
            if (-not $AndroidSdk) {
                $AndroidSdk = @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, "$env:LOCALAPPDATA/Android/Sdk", "${env:ProgramFiles(x86)}/Android/android-sdk" |
                    Where-Object { $_ -and (Test-Path -LiteralPath (Join-Path $_ 'platform-tools/adb.exe')) } | Select-Object -First 1)[0]
            }
            $adb = (Resolve-Path -LiteralPath (Join-Path $AndroidSdk 'platform-tools/adb.exe')).Path
            if (-not $Serial) {
                $devices = Invoke-Tool $adb @('devices') (Join-Path $run "$config-devices.log")
                $ready = @([regex]::Matches($devices, '(?m)^(\S+)\s+device\s*$') | ForEach-Object { $_.Groups[1].Value })
                if ($ready.Count -ne 1) { throw 'Select exactly one connected Android device with -Serial, or use -SkipDevice for build-only verification.' }
                $Serial = $ready[0]
            }
            $deviceAbi = (Invoke-Tool $adb @('-s', $Serial, 'shell', 'getprop', 'ro.product.cpu.abilist') (Join-Path $run "$config-device-abi.log")).Trim()
            if ($Abi -notin $deviceAbi.Split(',')) { throw "Device does not support $Abi" }
            $remote = '/data/local/tmp/udk-diagnostic-' + [Guid]::NewGuid().ToString('N')
            [void](Invoke-Tool $adb @('-s', $Serial, 'shell', 'mkdir', '-p', $remote) (Join-Path $run "$config-mkdir.log"))
            $runtimeAbi = if ($Abi -eq 'arm64-v8a') { 'aarch64-linux-android' } else { 'x86_64-linux-android' }
            $runtime = Join-Path $AndroidNdk "toolchains/llvm/prebuilt/windows-x86_64/sysroot/usr/lib/$runtimeAbi/libc++_shared.so"
            $files = @(Get-ChildItem -LiteralPath $bin -File | Where-Object { $_.Name -eq 'DiagnosticContract' -or $_.Extension -eq '.so' })
            foreach ($file in $files) {
                [void](Invoke-Tool $adb @('-s', $Serial, 'push', $file.FullName, "$remote/$($file.Name)") (Join-Path $run "$config-push-$($file.Name).log"))
            }
            [void](Invoke-Tool $adb @('-s', $Serial, 'push', $runtime, "$remote/libc++_shared.so") (Join-Path $run "$config-push-runtime.log"))
            [void](Invoke-Tool $adb @('-s', $Serial, 'shell', 'chmod', '755', "$remote/DiagnosticContract") (Join-Path $run "$config-chmod.log"))
        }

        foreach ($record in $current) {
            $record.Log = Join-Path $run "$config-$($record.Scenario).log"
            try {
                if ($Platform -eq 'Windows') {
                    $output = Invoke-Tool (Join-Path $bin 'DiagnosticContract.exe') @($record.Scenario, (Join-Path $run "results/$config/$($record.Scenario)")) $record.Log
                }
                else {
                    # Remote paths and scenario names are generated constants, never shell-quoted user input.
                    $remoteCommand = "cd $remote && LD_LIBRARY_PATH=$remote ./DiagnosticContract $($record.Scenario) $remote/logs/$($record.Scenario)"
                    $output = Invoke-Tool $adb @('-s', $Serial, 'shell', $remoteCommand) $record.Log
                }
                if ($output -notmatch ('(?m)^DIAGNOSTIC_PASS ' + $record.Scenario + '\s*$')) { throw 'Missing native success marker.' }
                $record.Execution = 'Passed'
            }
            catch { $record.Execution = 'Failed'; $record.Details = $_.Exception.Message; $failed = $true }
            Save-Report
        }
        if ($Platform -eq 'Android') {
            # Preserve device logs in the report; no recursive deletion is performed.
            [void](Invoke-Tool $adb @('-s', $Serial, 'pull', "$remote/logs", (Join-Path $run "$config-device-logs")) (Join-Path $run "$config-pull.log"))
        }
    }
}
catch {
    $failed = $true
    $failureMessage = $_.Exception.Message
    $records | Where-Object { $_.Execution -eq 'NotRun' } | ForEach-Object { $_.Details = $failureMessage }
    Write-Host $failureMessage
}
finally {
    Save-Report
    $records | Format-Table Platform, Configuration, Scenario, Build, Execution -AutoSize
    Write-Host "Report: $run"
}
if ($failed) { exit 1 }
exit 0