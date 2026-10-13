param([string]$CMake, [string]$NuGet = 'nuget.exe')

$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
. (Join-Path $repository 'Tests/Infrastructure/TestWorkspace.ps1')
. (Join-Path $repository 'Tests/Infrastructure/BuildTools.ps1')
$workspace = New-TestWorkspace $repository WorkingTree HEAD
$fixture = Join-Path $repository 'Tests/Fixtures/Libraries/HeaderOnly'
Get-ChildItem -LiteralPath $fixture -Force | Copy-Item -Destination $workspace.Library -Recurse -Force
& (Join-Path $workspace.Library 'Scripts/PowerShell/GenerateComponentProjects.ps1') -RepositoryRoot $workspace.Library
# Короткий путь предотвращает превышение MAX_PATH у CompilerId MSBuild.
$shortLibrary = Join-Path $repository ('!artifacts/nr-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
Copy-Item -LiteralPath $workspace.Library -Destination $shortLibrary -Recurse
$workspace.Library = $shortLibrary
$feed = Join-Path $workspace.Library '!artifacts/nuget-registry'
# Другой реестр и header-only цепочка обнаруживают привязку к рабочим компонентам.
& (Join-Path $repository 'Packages/NuGet/Build.ps1') -RepositoryPath $workspace.Library -Components HeaderProbe -CMake $CMake -NuGet $NuGet -LicenseFile (Join-Path $repository 'LICENSE') -OutputDirectory $feed
$version = (Get-Content (Join-Path $workspace.Library 'Version.json') -Raw | ConvertFrom-Json).version
foreach ($name in @('HeaderProbe', 'HeaderLeaf')) {
    if (-not (Test-Path (Join-Path $feed "UniversalDevKit.$name.$version.nupkg"))) { throw "Missing registry package: $name" }
}
if (Test-Path (Join-Path $feed "UniversalDevKit.Helpers.$version.nupkg")) { throw 'Unexpected hardcoded package.' }
$consumer = Join-Path $workspace.Root 'NuGetConsumer'
[void][IO.Directory]::CreateDirectory($consumer)
Copy-Item -LiteralPath (Join-Path $fixture 'Consumer.cpp') -Destination (Join-Path $consumer 'Main.cpp')
$templates = Join-Path $repository 'Tests/Fixtures/Consumers/NuGet'
$text = (Get-Content (Join-Path $templates 'Consumer.vcxproj.in') -Raw).Replace('Helpers', 'HeaderLeaf').Replace('Diagnostic', 'HeaderProbe').Replace('@VERSION@', $version)
$import = '  <Import Project="packages\UniversalDevKit.HeaderProbe.' + $version + '\build\native\UniversalDevKit.HeaderProbe.targets" />'
$text = $text.Replace('@DIAGNOSTIC_IMPORT@', $import).Replace('@DIAGNOSTIC_PROPS@', $import.Replace('.targets', '.props')).Replace('@TEST_DEFINITIONS@', '').Replace('@ROOTS@', 'HeaderProbe')
[IO.File]::WriteAllText((Join-Path $consumer 'Consumer.vcxproj'), $text.TrimEnd([char[]]"`r`n"), [Text.UTF8Encoding]::new($false))
$config = (Get-Content (Join-Path $templates 'packages.config.in') -Raw).Replace('Helpers', 'HeaderLeaf').Replace('Diagnostic', 'HeaderProbe').Replace('@VERSION@', $version)
[IO.File]::WriteAllText((Join-Path $consumer 'packages.config'), $config.TrimEnd([char[]]"`r`n"), [Text.UTF8Encoding]::new($false))
& $NuGet restore (Join-Path $consumer 'packages.config') -Source $feed -PackagesDirectory (Join-Path $consumer 'packages') -NoCache -DirectDownload -NonInteractive | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'Registry package restore failed.' }
$msbuild = Get-TestMSBuild
foreach ($configuration in @('Debug', 'Release')) {
    & $msbuild (Join-Path $consumer 'Consumer.vcxproj') /nologo /v:minimal /t:Rebuild /p:Platform=x64 "/p:Configuration=$configuration" /p:UniversalDevKitRuntime=Dynamic | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Header-only NuGet consumer failed.' }
    Invoke-TestApplication (Join-Path $consumer "out/$configuration/Consumer.exe") ''
}
Write-Host "PASS: registry-driven header-only NuGet packages. Workspace: $($workspace.Root)"