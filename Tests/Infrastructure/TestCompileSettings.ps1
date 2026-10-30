param([string]$CMake = 'C:/Program Files/Microsoft Visual Studio/18/Community/Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe')

$ErrorActionPreference = 'Stop'
$env:DOTNET_CLI_UI_LANGUAGE = 'en-US'
$env:VSLANG = '1033'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)
$repository = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $PSScriptRoot 'TestWorkspace.ps1')
. (Join-Path $PSScriptRoot 'BuildTools.ps1')
$workspace = New-TestWorkspace $repository WorkingTree HEAD
$shortLibrary = Join-Path $workspace.Root 'L'
$testRoot = [IO.Path]::GetFullPath((Join-Path $repository '!artifacts/tests')) + [IO.Path]::DirectorySeparatorChar
foreach ($path in @($workspace.Library, $shortLibrary)) {
    if (-not [IO.Path]::GetFullPath($path).StartsWith($testRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe test path.' }
}
Move-Item -LiteralPath $workspace.Library -Destination $shortLibrary
$workspace.Library = $shortLibrary
$fixture = Join-Path $repository 'Tests/Fixtures/Libraries/Compile'
Get-ChildItem -LiteralPath $fixture -Force | Copy-Item -Destination $workspace.Library -Recurse -Force
$generator = Join-Path $workspace.Library 'Scripts/PowerShell/GenerateComponentProjects.ps1'
& $generator -RepositoryRoot $workspace.Library
$sharedPath = Join-Path $workspace.Library 'Projects/MsBuild/CompileProbe/UniversalDevKit.CompileProbe.Shared.vcxitems'
[xml]$shared = Get-Content -LiteralPath $sharedPath -Raw
$items = @($shared.SelectNodes('//*[local-name()="ClCompile" and @Include]'))
if ($items.Count -ne 2) { throw 'Incorrect source count.' }
$build = Join-Path $workspace.Library '!artifacts/c'
& $CMake -S $workspace.Library -B $build -G 'Visual Studio 18 2026' -A x64
if ($LASTEXITCODE -ne 0) { throw 'CMake configure failed.' }
& $CMake --build $build --config Debug --parallel 4
if ($LASTEXITCODE -ne 0) { throw 'CMake compile settings build failed.' }
$msbuild = Get-TestMSBuild
$evaluation = & $msbuild (Join-Path $workspace.Library 'Consumer/Evaluate.proj') -getItem:ClCompile /nologo
if ($LASTEXITCODE -ne 0) { throw 'MSBuild evaluation failed.' }
$evaluatedItems = (($evaluation -join "`n") | ConvertFrom-Json).Items.ClCompile
foreach ($item in $evaluatedItems) {
    if ($item.Identity -in @('Before.cpp', 'After.cpp')) {
        if ($item.PreprocessorDefinitions -ne 'CONSUMER_ONLY' -or $item.PrecompiledHeader -ne 'Use' -or $item.AdditionalIncludeDirectories -match 'CompileProbe') {
            throw 'Component settings leaked to consumer sources.'
        }
    } elseif ($item.Identity.EndsWith('External.cpp')) {
        if ($item.PrecompiledHeader -ne 'NotUsing' -or $item.PreprocessorDefinitions -notmatch 'COMPILE_FILE=9') { throw 'File settings are missing.' }
    } elseif ($item.Identity.EndsWith('Value.cpp')) {
        if ($item.PrecompiledHeader -ne 'Use' -or $item.PreprocessorDefinitions -notmatch 'COMPILE_BASE=7' -or $item.PreprocessorDefinitions -match 'COMPILE_FILE') {
            throw 'Common compile settings or inheritance are incorrect.'
        }
    }
}
foreach ($variant in @('Static', 'Dynamic')) {
    $project = Join-Path $workspace.Library "Projects/MsBuild/CompileProbe/UniversalDevKit.CompileProbe.$variant.vcxproj"
    $intDir = Join-Path $workspace.Root "o/$variant/"
    & $msbuild $project /p:Configuration=Debug /p:Platform=x64 "/p:IntDir=$intDir" /v:minimal /nologo
    if ($LASTEXITCODE -ne 0) { throw "MSBuild compile settings build failed: $variant" }
}
Write-Host "PASS: common and per-file compile settings and PCH. Workspace: $($workspace.Root)"