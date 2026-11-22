#requires -Version 5.1
param([switch]$SkipBuild)

$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tool = Join-Path $repository 'Sources/Windows/UdkCli/Tools/ProjectTools/Generate.ps1'
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('UdkWinRT.' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$env:DOTNET_CLI_UI_LANGUAGE = 'en-US'
$env:VSLANG = '1033'
$packageSuffix = [Guid]::NewGuid().ToString('N').Substring(0, 8)
$packageVersion = '1.0.0-test.' + $packageSuffix
$dynamicPackageVersion = '1.0.1-test.' + $packageSuffix
try {
    Copy-Item -LiteralPath (Join-Path $repository 'Tests/Fixtures/WinRT') -Destination $temporary -Recurse
    $manifest = Join-Path $temporary 'Components.xml'
    & $tool -ManifestPath $manifest
    & $tool -ManifestPath $manifest -Check
    $native = Join-Path $temporary 'Projects/!Generated/MsBuild/Library/HelloWorld.WinRT/HelloWorld.WinRT.vcxproj'
    $projection = Join-Path (Split-Path -Parent $native) 'HelloWorld.WinRT.Projection.csproj'
    $app = Join-Path $temporary 'Projects/!Generated/MsBuild/Application/HelloWorld/HelloWorld.csproj'
    $export = [IO.File]::ReadAllText((Join-Path $temporary 'Projects/!Generated/Includes/UniversalDevKit/HelloWorld.Core/Export.g.h'))
    if (-not $export.Contains('UNIVERSALDEVKIT_HELLOWORLD_CORE_API') -or $export.Contains('UNIVERSALDEVKIT_HELLOWORLD.CORE')) { throw 'Invalid dotted export macro.' }
    if (-not [IO.File]::ReadAllText($projection).Contains('<ProjectReference') -or
        -not [IO.File]::ReadAllText($app).Contains('HelloWorld.WinRT.Projection.csproj')) { throw 'Missing producer projection reference.' }
    [xml]$projectionXml = Get-Content -LiteralPath $projection -Raw
    if ($projectionXml.SelectSingleNode('/Project/PropertyGroup/Platforms').InnerText -cne 'x64') { throw 'Projection platforms do not match the solution.' }
    if ($projectionXml.SelectSingleNode('/Project/PropertyGroup/PlatformTarget').InnerText -cne 'AnyCPU') { throw 'The managed projection must remain architecture-neutral.' }
    & $tool -ManifestPath $manifest -Clean
    if (Test-Path -LiteralPath $projection) { throw 'Cleanup left the generated projection project.' }
    if (-not (Test-Path -LiteralPath (Join-Path $temporary 'Sources/WinRT/Greeter.idl'))) { throw 'Cleanup removed an IDL source.' }
    & $tool -ManifestPath $manifest
    & $tool -ManifestPath $manifest -Check
    $applicationDescriptionPath = Join-Path $temporary 'Application.xml'
    [xml]$applicationDescription = Get-Content -LiteralPath $applicationDescriptionPath -Raw
    $files = $applicationDescription.SelectSingleNode('//Project/Files')
    [void]$files.ParentNode.RemoveChild($files)
    $applicationDescription.Save($applicationDescriptionPath)
    & $tool -ManifestPath $manifest
    foreach ($file in @('App.g.cs', 'App.g.xaml', 'MainWindow.g.cs', 'MainWindow.g.xaml')) {
        if ((Test-Path -LiteralPath (Join-Path (Split-Path -Parent $app) $file)) -or [IO.File]::ReadAllText($app).Contains($file)) {
            throw "ProjectTools generated a WinUI source: $file"
        }
    }
    Copy-Item -LiteralPath (Join-Path $repository 'Tests/Fixtures/WinRT/Application.xml') -Destination $applicationDescriptionPath
    & $tool -ManifestPath $manifest
    & $tool -ManifestPath $manifest -Check
    if ($SkipBuild) { return }
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    $installation = & $vswhere -latest -products '*' -requires Microsoft.Component.MSBuild -property installationPath
    if (-not $installation) { throw 'Visual Studio MSBuild is required for the WinRT integration test.' }
    $msbuild = Join-Path $installation 'MSBuild/Current/Bin/MSBuild.exe'
    function Build([string]$Project, [string[]]$Arguments) {
        & $msbuild $Project /nologo /v:quiet /p:Configuration=Debug /p:Platform=x64 @Arguments
        if ($LASTEXITCODE) { throw "MSBuild failed: $Project" }
    }
    function VerifyApplication([string]$Executable) {
        $result = Join-Path $temporary ('result.' + [Guid]::NewGuid().ToString('N') + '.txt')
        $process = Start-Process -FilePath $Executable -WorkingDirectory (Split-Path -Parent $Executable) -ArgumentList @('--udk-verify', ('"' + $result + '"')) -WindowStyle Hidden -PassThru
        if (-not $process.WaitForExit(30000)) { $process.Kill(); throw 'Application verification timed out.' }
        if ($process.ExitCode -or -not (Test-Path -LiteralPath $result) -or [IO.File]::ReadAllText($result) -cne 'Hello, World!') { throw 'WinUI -> WinRT -> Core activation failed.' }
    }
    Build (Join-Path $temporary 'HelloWorld.sln') @('/restore')
    $exe = @(Get-ChildItem (Join-Path $temporary '!artifacts/projects/Windows/msbuild/HelloWorld/bin') -Recurse -Filter HelloWorld.exe)
    if ($exe.Count -ne 1) { throw 'Expected one application executable.' }
    VerifyApplication $exe[0].FullName
    $fragment = Join-Path $temporary '!artifacts/projects/Windows/msbuild/HelloWorld.WinRT/x64/Debug/activation.g.manifest'
    if ([IO.File]::ReadAllText($fragment) -notmatch 'HelloWorld.WinRT.Greeter') { throw 'WinMD activation metadata was not extracted.' }
    $manifestAssembly = Join-Path $temporary '!artifacts/projects/Windows/msbuild/WinRT.ManifestTasks/bin/Debug/netstandard2.0/UniversalDevKit.WinRT.ManifestTasks.dll'
    $mergeProject = Join-Path $temporary 'ManifestMerge.proj'
    $mergeOutput = Join-Path $temporary 'merge-test.manifest'
    Build $mergeProject @('/t:Merge', ('/p:ManifestTasksAssembly=' + $manifestAssembly), ('/p:MergeOutput=' + $mergeOutput))
    [xml]$mergedManifest = Get-Content -LiteralPath $mergeOutput -Raw
    if ($mergedManifest.SelectNodes('//*[local-name()="activatableClass"]').Count -ne 1 -or
        $mergedManifest.SelectSingleNode('//*[local-name()="assemblyIdentity"]').GetAttribute('name') -cne 'Preserved.Identity') { throw 'Manifest merging duplicated a registration or lost the base identity.' }
    & $msbuild $mergeProject /nologo /v:quiet /t:Conflict ('/p:ManifestTasksAssembly=' + $manifestAssembly) ('/p:MergeOutput=' + $mergeOutput) *> $null
    if ($LASTEXITCODE -eq 0) { throw 'Conflicting WinRT registration was accepted.' }
    Build $projection @('/t:Pack', ('/p:PackageVersion=' + $packageVersion), ('/p:PackageOutputPath=' + (Join-Path $temporary 'feed')))
    $consumer = Join-Path $temporary 'NuGetConsumer/Consumer.csproj'
    [xml]$consumerProject = Get-Content -LiteralPath $consumer -Raw
    $consumerProject.SelectSingleNode('//PackageReference[@Include="HelloWorld.WinRT.Projection"]').SetAttribute('Version', $packageVersion)
    $consumerProject.Save($consumer)
    $consumerRestore = @('/restore', ('/p:RestoreAdditionalProjectSources=' + (Join-Path $temporary 'feed')),
        ('/p:RestorePackagesPath=' + (Join-Path $temporary 'consumer-packages')),
        ('/p:RestoreFallbackFolders=' + (Join-Path $env:USERPROFILE '.nuget/packages')))
    Build $consumer $consumerRestore
    $consumerExe = @(Get-ChildItem (Join-Path $temporary 'NuGetConsumer/bin') -Recurse -Filter Consumer.exe)
    VerifyApplication $consumerExe[0].FullName
    $publish = Join-Path $temporary 'publish'
    Build $consumer @('/t:Publish', ('/p:PublishDir=' + $publish + '\'), ('/p:RestorePackagesPath=' + (Join-Path $temporary 'consumer-packages')))
    VerifyApplication (Join-Path $publish 'Consumer.exe')
    $generatedProjection = @(Get-ChildItem (Join-Path $temporary 'NuGetConsumer/obj') -Recurse -Filter '*.cs' | Where-Object { $_.FullName -match 'Generated Files|cswinrt' })
    if ($generatedProjection.Count) { throw 'The NuGet consumer generated a projection.' }
    [xml]$winrtDescription = Get-Content -LiteralPath (Join-Path $temporary 'WinRT.xml') -Raw
    $winrtDescription.SelectSingleNode('//Dependency').SetAttribute('linkage', 'dynamic')
    $winrtDescription.Save((Join-Path $temporary 'WinRT.xml'))
    & $tool -ManifestPath $manifest
    Build (Join-Path $temporary 'HelloWorld.sln') @('/restore')
    $coreDll = Join-Path $exe[0].DirectoryName 'HelloWorld.Core.Dynamic.dll'
    if (-not (Test-Path -LiteralPath $coreDll)) { throw 'The dynamic Core DLL was not delivered to the application.' }
    VerifyApplication $exe[0].FullName
    Build $projection @('/t:Pack', ('/p:PackageVersion=' + $dynamicPackageVersion), ('/p:PackageOutputPath=' + (Join-Path $temporary 'feed')))
    [xml]$consumerProject = Get-Content -LiteralPath $consumer -Raw
    $consumerProject.SelectSingleNode('//PackageReference[@Include="HelloWorld.WinRT.Projection"]').SetAttribute('Version', $dynamicPackageVersion)
    $consumerProject.Save($consumer)
    Build $consumer $consumerRestore
    if (-not (Test-Path -LiteralPath (Join-Path $consumerExe[0].DirectoryName 'HelloWorld.Core.Dynamic.dll'))) { throw 'NuGet did not deliver the dynamic Core DLL.' }
    VerifyApplication $consumerExe[0].FullName
    Build $consumer @('/t:Publish', ('/p:PublishDir=' + $publish + '\'), ('/p:RestorePackagesPath=' + (Join-Path $temporary 'consumer-packages')))
    if (-not (Test-Path -LiteralPath (Join-Path $publish 'HelloWorld.Core.Dynamic.dll'))) { throw 'Publish did not deliver the dynamic Core DLL.' }
    VerifyApplication (Join-Path $publish 'Consumer.exe')
    & $tool -ManifestPath $manifest -Check
    [xml]$registry = Get-Content -LiteralPath $manifest -Raw
    $extra = $registry.CreateElement('Component')
    $extra.InnerText = 'ExtraWinRT.xml'
    [void]$registry.ComponentRegistry.Components.AppendChild($extra)
    $registry.Save($manifest)
    $dependency = $winrtDescription.CreateElement('Dependency')
    $dependency.SetAttribute('component', 'HelloWorld.ExtraWinRT')
    $dependency.SetAttribute('visibility', 'public')
    $dependency.SetAttribute('linkage', 'dynamic')
    [void]$winrtDescription.SelectSingleNode('//Dependencies').AppendChild($dependency)
    $winrtDescription.Save((Join-Path $temporary 'WinRT.xml'))
    $idl = Join-Path $temporary 'Sources/WinRT/Greeter.idl'
    [IO.File]::WriteAllText($idl, [IO.File]::ReadAllText($idl).Replace('String GetMessage();', 'String GetMessage();' + "`n        HelloWorld.ExtraWinRT.ExtraGreeter CreateOther();"))
    $header = Join-Path $temporary 'Sources/WinRT/Greeter.h'
    [IO.File]::WriteAllText($header, [IO.File]::ReadAllText($header).Replace('#include "Greeter.g.h"', '#include "Greeter.g.h"' + "`n#include <winrt/HelloWorld.ExtraWinRT.h>").Replace('winrt::hstring GetMessage();', 'winrt::hstring GetMessage();' + "`n        winrt::HelloWorld::ExtraWinRT::ExtraGreeter CreateOther();"))
    $source = Join-Path $temporary 'Sources/WinRT/Greeter.cpp'
    [IO.File]::WriteAllText($source, [IO.File]::ReadAllText($source) + "`nwinrt::HelloWorld::ExtraWinRT::ExtraGreeter winrt::HelloWorld::WinRT::implementation::Greeter::CreateOther() { return winrt::HelloWorld::ExtraWinRT::ExtraGreeter{}; }")
    foreach ($file in @('App.xaml.cs', 'MainWindow.xaml.cs')) {
        $source = Join-Path $temporary ('Sources/Application/' + $file)
        [IO.File]::WriteAllText($source, [IO.File]::ReadAllText($source).Replace('new global::HelloWorld.WinRT.Greeter().GetMessage()', 'new global::HelloWorld.WinRT.Greeter().CreateOther().GetMessage()'))
    }
    & $tool -ManifestPath $manifest
    Build (Join-Path $temporary 'HelloWorld.sln') @('/restore')
    VerifyApplication $exe[0].FullName
    $transitiveVersion = '1.0.2-test.' + $packageSuffix
    $extraProjection = Join-Path $temporary 'Projects/!Generated/MsBuild/Library/HelloWorld.ExtraWinRT/HelloWorld.ExtraWinRT.Projection.csproj'
    Build $extraProjection @('/t:Pack', ('/p:PackageVersion=' + $transitiveVersion), ('/p:PackageOutputPath=' + (Join-Path $temporary 'feed')))
    Build $projection @('/t:Pack', ('/p:PackageVersion=' + $transitiveVersion), ('/p:PackageOutputPath=' + (Join-Path $temporary 'feed')))
    $consumerProject.SelectSingleNode('//PackageReference[@Include="HelloWorld.WinRT.Projection"]').SetAttribute('Version', $transitiveVersion)
    $consumerProject.Save($consumer)
    Build $consumer $consumerRestore
    VerifyApplication $consumerExe[0].FullName
    $merged = @(Get-ChildItem (Join-Path $temporary 'NuGetConsumer/obj') -Recurse -Filter UniversalDevKit.Application.g.manifest)
    if (-not [IO.File]::ReadAllText($merged[0].FullName).Contains('HelloWorld.ExtraWinRT.ExtraGreeter')) { throw 'Transitive WinRT activation was not merged.' }
    Build $consumer @('/t:Publish', ('/p:PublishDir=' + $publish + '\'), ('/p:RestorePackagesPath=' + (Join-Path $temporary 'consumer-packages')))
    VerifyApplication (Join-Path $publish 'Consumer.exe')
    & $tool -ManifestPath $manifest -Check
    Write-Host 'PASS: WinRT project references, WinMD manifests, producer projection, local NuGet and publish activation.'
} finally {
    $resolved = [IO.Path]::GetFullPath($temporary)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'UdkWinRT.*') { throw 'Unexpected WinRT test directory.' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}