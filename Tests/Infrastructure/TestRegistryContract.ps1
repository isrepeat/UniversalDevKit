param([string]$CMake = 'C:/Program Files/Microsoft Visual Studio/18/Community/Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe')

$env:DOTNET_CLI_UI_LANGUAGE = 'en-US'
$env:VSLANG = '1033'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)

$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $PSScriptRoot 'TestWorkspace.ps1')
. (Join-Path $PSScriptRoot 'BuildTools.ps1')
$workspace = New-TestWorkspace $repository WorkingTree HEAD
$fixture = Join-Path $repository 'Tests/Fixtures/Libraries/HeaderOnly'
Get-ChildItem -LiteralPath $fixture -Force | Copy-Item -Destination $workspace.Library -Recurse -Force
$generator = Join-Path $workspace.Library 'Scripts/PowerShell/GenerateComponentProjects.ps1'

function InvokeChecked([string]$Tool, [string[]]$Arguments) {
    & $Tool @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Command failed: $Tool" }
}

try {
    # 1. Header-only creates Shared and INTERFACE targets without empty archives or DLLs.
    & $generator -RepositoryRoot $workspace.Library
    . (Join-Path $workspace.Library 'Scripts/PowerShell/Modules/Module.Udk.Connection/Private/ConnectionPlan.ps1')
    $registry = @{
        HeaderProbe = [pscustomobject]@{ Kind = 'headerOnly'; Dependencies = @() }
        Parent = [pscustomobject]@{ Kind = 'compiled'; Dependencies = @([pscustomobject]@{ Component = 'HeaderProbe'; Visibility = 'public'; Linkage = 'same' }) }
    }
    $graph = Resolve-UdkLinkageGraph @('Parent') @{ Parent = 'Dynamic' } $registry
    if ($graph.ResolvedModes.HeaderProbe -ne 'Shared' -or 'HeaderProbe' -in $graph.LinkComponents) { throw 'Header-only inherited binary linkage' }
    $rejected = $false
    try { Resolve-UdkLinkageGraph @('HeaderProbe') @{ HeaderProbe = 'Static' } $registry | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw 'Header-only accepted Static mode' }
    if (Test-Path (Join-Path $workspace.Library 'Projects/MsBuild/HeaderProbe/UniversalDevKit.HeaderProbe.Static.vcxproj')) { throw 'Unexpected Static project' }
    if (Test-Path (Join-Path $workspace.Library 'Projects/MsBuild/HeaderProbe/UniversalDevKit.HeaderProbe.Dynamic.vcxproj')) { throw 'Unexpected Dynamic project' }
    $build = Join-Path $workspace.Library '!artifacts/h'
    $install = Join-Path $workspace.Root 'install'
    InvokeChecked $CMake @('-S', $workspace.Library, '-B', $build, '-G', 'Visual Studio 18 2026', '-A', 'x64', '-DUniversalDevKit_BUILD_STATIC=OFF', '-DUniversalDevKit_BUILD_DYNAMIC=OFF', "-DCMAKE_INSTALL_PREFIX=$install")
    InvokeChecked $CMake @('--install', $build, '--config', 'Debug')
    $consumerBuild = Join-Path $workspace.Root 'consumer-build'
    InvokeChecked $CMake @('-S', (Join-Path $workspace.Library 'Consumer'), '-B', $consumerBuild, '-G', 'Visual Studio 18 2026', '-A', 'x64', "-DCMAKE_PREFIX_PATH=$install")
    InvokeChecked $CMake @('--build', $consumerBuild, '--config', 'Debug')
    InvokeChecked (Join-Path $consumerBuild 'Debug/HeaderOnlyConsumer.exe') @()
    $project = Join-Path $workspace.Library 'Consumer/Shared.vcxproj'
    Copy-Item -LiteralPath ($project + '.in') -Destination $project
    InvokeChecked (Get-TestMSBuild) @($project, '/p:Configuration=Debug', '/p:Platform=x64', '/v:minimal', '/nologo')
    InvokeChecked (Join-Path $workspace.Library 'Consumer/bin/Shared.exe') @()

    # 2. Both readers must reject the same invalid descriptions.
    foreach ($case in Get-ChildItem (Join-Path $repository 'Tests/Fixtures/RegistryContract') -Filter '*.json') {
        Copy-Item -LiteralPath $case.FullName -Destination (Join-Path $workspace.Library 'Projects/Components/HeaderProbe.json') -Force
        $rejected = $false
        try { & $generator -RepositoryRoot $workspace.Library -Check } catch { $rejected = $true }
        if (-not $rejected) { throw "MSBuild accepted $($case.Name)" }
        & $CMake '-S' $workspace.Library '-B' $build | Out-Host
        if ($LASTEXITCODE -eq 0) { throw "CMake accepted $($case.Name)" }
        Write-Host "PASS: both readers rejected $($case.Name)"
    }
    Copy-Item -LiteralPath (Join-Path $fixture 'Projects/Components/HeaderProbe.json') -Destination (Join-Path $workspace.Library 'Projects/Components/HeaderProbe.json') -Force
    foreach ($case in Get-ChildItem (Join-Path $repository 'Tests/Fixtures/RegistryContract/Manifest') -Filter '*.json') {
        Copy-Item -LiteralPath $case.FullName -Destination (Join-Path $workspace.Library 'Components.json') -Force
        $rejected = $false
        try { & $generator -RepositoryRoot $workspace.Library -Check } catch { $rejected = $true }
        if (-not $rejected) { throw "MSBuild accepted manifest $($case.Name)" }
        & $CMake '-S' $workspace.Library '-B' $build | Out-Host
        if ($LASTEXITCODE -eq 0) { throw "CMake accepted manifest $($case.Name)" }
        Write-Host "PASS: both readers rejected manifest $($case.Name)"
    }
    Write-Host "PASS: registry contract. Workspace: $($workspace.Root)"
}
catch {
    Write-Host "Preserved workspace: $($workspace.Root)"
    throw
}