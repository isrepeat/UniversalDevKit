param([string]$CMake = 'cmake', [string]$Generator = 'Visual Studio 18 2026')

$env:DOTNET_CLI_UI_LANGUAGE = 'en-US'
$env:VSLANG = '1033'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)

$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
. (Join-Path $repository 'Scripts/PowerShell/ArtifactDirectories.ps1')
$run = Reset-UdkArtifactDirectory -Root (Join-Path $repository '!artifacts/tests') -Path (Join-Path $repository '!artifacts/tests/TestBinaryCompatibility')
$source = Join-Path $repository 'Tests/Fixtures/Consumers/BinaryCompatibility'
function InvokeCMake([string[]]$Arguments) {
    & $CMake @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "CMake failed: $($Arguments -join ' ')" }
}
function AssertFails([string[]]$Arguments, [string]$Pattern) {
    $ErrorActionPreference = 'Continue'
    $output = & $CMake @Arguments 2>&1
    if ($LASTEXITCODE -eq 0 -or ($output -join "`n") -notmatch $Pattern) {
        throw "Expected rejection ($Pattern): $($output -join '`n')"
    }
    Write-Output "Expected rejection: $Pattern"
}

foreach ($runtime in @('Dynamic', 'Static')) {
    $build = Join-Path $run "build-$runtime"
    $prefix = Join-Path $run "install-$runtime"
    InvokeCMake @('-S', $repository, '-B', $build, '-G', $Generator, '-A', 'x64', '-DCMAKE_CONFIGURATION_TYPES=Debug;Release', "-DUniversalDevKitRuntime=$runtime")
    foreach ($configuration in @('Debug', 'Release')) {
        InvokeCMake @('--build', $build, '--config', $configuration)
        # Validate explicit --prefix just like CMAKE_INSTALL_PREFIX.
        InvokeCMake @('--install', $build, '--config', $configuration, '--prefix', $prefix)
        $recordPath = Join-Path $prefix "lib/cmake/UniversalDevKit/UniversalDevKit.Build-$configuration.json"
        $record = Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json
        if ($record.schemaVersion -ne 1 -or $record.runtime -ne $runtime -or $record.configuration -ne $configuration -or $record.architecture -ne 'x64') {
            throw 'Invalid binary metadata'
        }
        foreach ($file in $record.runtimeFiles) {
            if (-not (Test-Path -LiteralPath (Join-Path $prefix $file) -PathType Leaf)) { throw "Missing runtime file: $file" }
        }
        foreach ($component in $record.components) {
            if (-not (Test-Path -LiteralPath (Join-Path $prefix $component.linkFile) -PathType Leaf)) { throw 'Missing linker artifact' }
        }
        foreach ($variant in @('Static', 'Dynamic')) {
            $consumer = Join-Path $run "consumer-$runtime-$configuration-$variant"
            $crt = 'MultiThreaded'
            if ($configuration -eq 'Debug') { $crt += 'Debug' }
            if ($runtime -eq 'Dynamic') { $crt += 'DLL' }
            InvokeCMake @('-S', $source, '-B', $consumer, '-G', $Generator, '-A', 'x64', "-DCMAKE_CONFIGURATION_TYPES=$configuration", "-DCMAKE_PREFIX_PATH=$prefix", "-DTEST_VARIANT=$variant", "-DTEST_RUNTIME=$crt")
            InvokeCMake @('--build', $consumer, '--config', $configuration)
            & (Join-Path $consumer "$configuration/consumer.exe")
            if ($LASTEXITCODE -ne 0) { throw 'Compatible consumer failed' }
        }
    }
}

# Stop incompatible installation before overwriting binaries.
$mdPrefix = Join-Path $run 'install-Dynamic'
$before = (Get-FileHash (Join-Path $mdPrefix 'bin/universaldevkit_diagnostictest_dynamic.dll')).Hash
AssertFails @('--install', (Join-Path $run 'build-Static'), '--config', 'Release', '--prefix', $mdPrefix) 'incompatible package'
if ((Get-FileHash (Join-Path $mdPrefix 'bin/universaldevkit_diagnostictest_dynamic.dll')).Hash -ne $before) { throw 'Rejected install changed binary' }

foreach ($case in @('CRT', 'Iterator')) {
    $consumer = Join-Path $run "rejected-$case"
    $arguments = @('-S', $source, '-B', $consumer, '-G', $Generator, '-A', 'x64', '-DCMAKE_CONFIGURATION_TYPES=Release', "-DCMAKE_PREFIX_PATH=$mdPrefix", '-DTEST_VARIANT=Static')
    if ($case -eq 'CRT') { $arguments += '-DTEST_RUNTIME=MultiThreaded' } else { $arguments += '-DTEST_ITERATOR_ABI=1' }
    InvokeCMake $arguments
    AssertFails @('--build', $consumer, '--config', 'Release') 'UniversalDevKit package.*mismatch'
}
AssertFails @('-S', $source, '-B', (Join-Path $run 'wrong-compiler'), '-G', $Generator, '-A', 'x64', '-DCMAKE_CONFIGURATION_TYPES=Release', "-DCMAKE_PREFIX_PATH=$mdPrefix", '-DTEST_VARIANT=Static', '-DTEST_COMPILER_VERSION=0.0') 'compiler mismatch'
AssertFails @('-S', $source, '-B', (Join-Path $run 'wrong-toolset'), '-G', $Generator, '-A', 'x64', '-DCMAKE_CONFIGURATION_TYPES=Release', "-DCMAKE_PREFIX_PATH=$mdPrefix", '-DTEST_VARIANT=Static', '-DTEST_TOOLSET=unsupported') 'toolset mismatch'
AssertFails @('-S', $source, '-B', (Join-Path $run 'wrong-architecture'), '-G', $Generator, '-A', 'x64', '-DCMAKE_CONFIGURATION_TYPES=Release', "-DCMAKE_PREFIX_PATH=$mdPrefix", '-DTEST_VARIANT=Static', '-DTEST_ARCHITECTURE=arm64') 'architecture mismatch'
Write-Output 'Binary compatibility and install prefix checks passed.'