param([string]$CMake = 'cmake', [string]$Generator = 'Visual Studio 18 2026')

$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$run = Join-Path $repository ('!artifacts/Windows-x64/cmake/PackageTest-' + [Guid]::NewGuid().ToString('N'))
$build = Join-Path $run 'build'
$install = Join-Path $run 'install'
$relocated = Join-Path $run 'relocated'
$consumer = Join-Path $run 'consumer'

function InvokeCMake([string[]]$Arguments) {
    & $CMake @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "CMake failed: $($Arguments -join ' ')"
    }
}

# Проверяем обе конфигурации в одном установленном пакете.
InvokeCMake @('-S', $repository, '-B', $build, '-G', $Generator, '-A', 'x64', "-DCMAKE_INSTALL_PREFIX=$install")
foreach ($configuration in @('Debug', 'Release')) {
    InvokeCMake @('--build', $build, '--config', $configuration)
    InvokeCMake @('--install', $build, '--config', $configuration)
}

# Переносим только установленный пакет; исходный prefix больше не существует.
Move-Item -LiteralPath $install -Destination $relocated
InvokeCMake @('-S', (Join-Path $repository 'Tests/CmakePackage'), '-B', $consumer, '-G', $Generator, '-A', 'x64', "-DCMAKE_PREFIX_PATH=$relocated")
foreach ($configuration in @('Debug', 'Release')) {
    InvokeCMake @('--build', $consumer, '--config', $configuration)
    $ctest = Join-Path (Split-Path -Parent (Get-Command $CMake).Source) 'ctest.exe'
    & $ctest --test-dir $consumer -C $configuration --output-on-failure
    if ($LASTEXITCODE -ne 0) {
        throw "Package consumer failed: $configuration"
    }
}

# Неизвестный обязательный компонент обязан отклоняться при конфигурации.
& $CMake -S (Join-Path $repository 'Tests/CmakePackage') -B (Join-Path $run 'invalid') -G $Generator -A x64 "-DCMAKE_PREFIX_PATH=$relocated" -DUDK_TEST_COMPONENT=Unknown
if ($LASTEXITCODE -eq 0) {
    throw 'Unknown component was accepted.'
}
Write-Output 'Relocated package: Static/Dynamic, Debug/Release and unknown component checks passed.'