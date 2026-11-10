param([string]$CMake, [string]$NuGet = 'nuget.exe')

$env:DOTNET_CLI_UI_LANGUAGE = 'en-US'
$env:VSLANG = '1033'

$ErrorActionPreference = 'Stop'

# Согласуем кодировку консоли и native pipeline в Windows PowerShell 5.1.
$utf8Encoding = [Text.UTF8Encoding]::new($false)
[Console]::InputEncoding = $utf8Encoding
[Console]::OutputEncoding = $utf8Encoding
$OutputEncoding = $utf8Encoding
$repository = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$NuGet = & (Join-Path $repository 'Scripts/PowerShell/GetNuGet.ps1') -LocalPath $NuGet
. (Join-Path $repository 'Tests/Infrastructure/TestWorkspace.ps1')
. (Join-Path $repository 'Tests/Infrastructure/BuildTools.ps1')
$workspace = New-TestWorkspace $repository WorkingTree HEAD
$fixture = Join-Path $repository 'Tests/Fixtures/Libraries/HeaderOnly'
Get-ChildItem -LiteralPath $fixture -Force | Copy-Item -Destination $workspace.Library -Recurse -Force
& (Join-Path $workspace.Library 'Sources/Windows/ProjectTools/Generate.ps1') -ManifestPath (Join-Path $workspace.Library 'Components.json')
# Короткий путь предотвращает превышение MAX_PATH у CompilerId MSBuild.
$shortLibrary = Join-Path $workspace.Root 'L'
Copy-Item -LiteralPath $workspace.Library -Destination $shortLibrary -Recurse
$workspace.Library = $shortLibrary
$feed = Join-Path $workspace.Library '!artifacts/packages/nuget'
# Другой реестр и header-only цепочка обнаруживают привязку к рабочим компонентам.
& (Join-Path $repository 'Packages/Build/Build.ps1') -RepositoryPath $workspace.Library -PackagePath Packages/CrossPlatform/HeaderProbe/Package.json -CMake $CMake -NuGet $NuGet -OutputDirectory $feed
$feed = Join-Path $feed 'HeaderProbe'
$version = (Get-Content (Join-Path $workspace.Library 'Version.json') -Raw | ConvertFrom-Json).version
foreach ($name in @('HeaderProbe', 'HeaderLeaf')) {
    if (-not (Test-Path (Join-Path $feed "UniversalDevKit.$name.$version.nupkg"))) { throw "Missing registry package: $name" }
}
$consumer = Join-Path $workspace.Root 'NuGetConsumer'
[void][IO.Directory]::CreateDirectory($consumer)
Copy-Item -LiteralPath (Join-Path $fixture 'Consumer.cpp') -Destination (Join-Path $consumer 'Main.cpp')
$templates = Join-Path $repository 'Tests/Fixtures/Consumers/NuGet'
$text = (Get-Content (Join-Path $templates 'Consumer.vcxproj.in') -Raw).Replace('{{LEAF_COMPONENT}}', 'HeaderLeaf').Replace('{{ROOT_COMPONENT}}', 'HeaderProbe').Replace('{{VERSION}}', $version)
$import = '  <Import Project="packages\UniversalDevKit.HeaderProbe.' + $version + '\build\native\UniversalDevKit.HeaderProbe.targets" />'
$text = $text.Replace('{{ROOT_IMPORT}}', $import).Replace('{{ROOT_PROPS}}', $import.Replace('.targets', '.props')).Replace('{{TEST_DEFINITIONS}}', '').Replace('{{ROOTS}}', 'HeaderProbe')
[IO.File]::WriteAllText((Join-Path $consumer 'Consumer.vcxproj'), $text.TrimEnd([char[]]"`r`n"), [Text.UTF8Encoding]::new($false))
$config = (Get-Content (Join-Path $templates 'packages.config.in') -Raw).Replace('{{LEAF_COMPONENT}}', 'HeaderLeaf').Replace('{{ROOT_COMPONENT}}', 'HeaderProbe').Replace('{{VERSION}}', $version)
[IO.File]::WriteAllText((Join-Path $consumer 'packages.config'), $config.TrimEnd([char[]]"`r`n"), [Text.UTF8Encoding]::new($false))
& $NuGet restore (Join-Path $consumer 'packages.config') -Source $feed -PackagesDirectory (Join-Path $consumer 'packages') -NoCache -DirectDownload -NonInteractive -ForceEnglishOutput | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'Registry package restore failed.' }
$msbuild = Get-TestMSBuild
foreach ($configuration in @('Debug', 'Release')) {
    & $msbuild (Join-Path $consumer 'Consumer.vcxproj') /nologo /v:minimal /t:Rebuild /p:Platform=x64 "/p:Configuration=$configuration" /p:UniversalDevKitRuntime=Dynamic | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Header-only NuGet consumer failed.' }
    Invoke-TestApplication (Join-Path $consumer "out/$configuration/Consumer.exe") ''
}
Write-Host "PASS: registry-driven header-only NuGet packages. Workspace: $($workspace.Root)"