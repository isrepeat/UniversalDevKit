param(
    [string]$CMake = 'C:/Program Files/Microsoft Visual Studio/18/Community/Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe'
)

$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $PSScriptRoot 'TestWorkspace.ps1')
. (Join-Path $PSScriptRoot 'BuildTools.ps1')
$workspace = New-TestWorkspace $repository WorkingTree HEAD
$fixture = Join-Path $repository 'Tests/Fixtures/Libraries/Generated'
Get-ChildItem -LiteralPath $fixture -Force | Copy-Item -Destination $workspace.Library -Recurse -Force

function InvokeChecked([string]$Tool, [string[]]$Arguments) {
    & $Tool @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Command failed: $Tool ($LASTEXITCODE)" }
}

try {
    # 1. Создаём проекты только в изолированной копии UDK.
    & (Join-Path $workspace.Library 'Scripts/PowerShell/GenerateComponentProjects.ps1') -RepositoryRoot $workspace.Library
    $build = Join-Path $workspace.Library '!artifacts/g'
    $install = Join-Path $workspace.Root 'install'
    InvokeChecked $CMake @('-S', $workspace.Library, '-B', $build, '-G', 'Visual Studio 18 2026', '-A', 'x64', "-DCMAKE_INSTALL_PREFIX=$install")
    InvokeChecked $CMake @('--build', $build, '--config', 'Debug', '--parallel', '4')
    $header = Join-Path $build 'generated/GeneratedProbe/Static/Includes/UniversalDevKit/GeneratedProbe/Generated/Value.h'
    $firstWrite = (Get-Item -LiteralPath $header).LastWriteTimeUtc
    InvokeChecked $CMake @('--build', $build, '--config', 'Debug', '--parallel', '4')
    if ((Get-Item -LiteralPath $header).LastWriteTimeUtc -ne $firstWrite) { throw 'Unnecessary CMake regeneration' }
    # Изменение времени входа моделирует обновление файла без изменения исходного fixture.
    $input = Join-Path $workspace.Library 'Projects/Generation/Input.txt'
    (Get-Item -LiteralPath $input).LastWriteTimeUtc = [DateTime]::UtcNow.AddSeconds(2)
    InvokeChecked $CMake @('--build', $build, '--config', 'Debug', '--parallel', '4')
    if ((Get-Item -LiteralPath $header).LastWriteTimeUtc -eq $firstWrite) { throw 'CMake did not regenerate changed input' }
    InvokeChecked $CMake @('--install', $build, '--config', 'Debug')

    # 2. Пакетный consumer использует готовые заголовки без запуска генератора.
    $consumerBuild = Join-Path $workspace.Root 'consumer-build'
    InvokeChecked $CMake @('-S', (Join-Path $workspace.Library 'Consumer'), '-B', $consumerBuild, '-G', 'Visual Studio 18 2026', '-A', 'x64', '-DCMAKE_CONFIGURATION_TYPES=Debug', "-DCMAKE_PREFIX_PATH=$install")
    InvokeChecked $CMake @('--build', $consumerBuild, '--config', 'Debug')
    InvokeChecked (Join-Path $consumerBuild 'Debug/GeneratedConsumer.exe') @()

    # 3. Shared генерирует реализацию внутри IntDir потребителя.
    $msbuild = Get-TestMSBuild
    $project = Join-Path $workspace.Library 'Consumer/Shared.vcxproj'
    Copy-Item -LiteralPath ($project + '.in') -Destination $project
    $arguments = @($project, '/p:Configuration=Debug', '/p:Platform=x64', "/p:UniversalDevKitHostCMake=$CMake", '/v:minimal', '/nologo')
    InvokeChecked $msbuild $arguments
    InvokeChecked (Join-Path $workspace.Library 'Consumer/bin/Shared.exe') @()
    $sharedHeader = Join-Path $workspace.Library 'Consumer/obj/UniversalDevKit/GeneratedProbe/generated/Includes/UniversalDevKit/GeneratedProbe/Generated/Value.h'
    $firstWrite = (Get-Item -LiteralPath $sharedHeader).LastWriteTimeUtc
    InvokeChecked $msbuild $arguments
    if ((Get-Item -LiteralPath $sharedHeader).LastWriteTimeUtc -ne $firstWrite) { throw 'Unnecessary MSBuild regeneration' }
    (Get-Item -LiteralPath $input).LastWriteTimeUtc = [DateTime]::UtcNow
    InvokeChecked $msbuild $arguments
    if ((Get-Item -LiteralPath $sharedHeader).LastWriteTimeUtc -eq $firstWrite) { throw 'MSBuild did not regenerate changed input' }
    InvokeChecked (Join-Path $workspace.Library 'Consumer/bin/Shared.exe') @()
    # Отдельный IntDir заставляет выполнить генерацию без доступного host-инструмента.
    & $msbuild $project '/p:Configuration=Debug' '/p:Platform=x64' '/p:IntDir=obj-missing-tool/' '/p:UniversalDevKitHostCMake=' '/v:minimal' '/nologo' | Out-Host
    if ($LASTEXITCODE -eq 0) { throw 'Missing host tool was accepted' }
    Write-Host "PASS: build extensions. Workspace: $($workspace.Root)"
}
catch {
    Write-Host "Preserved workspace: $($workspace.Root)"
    throw
}