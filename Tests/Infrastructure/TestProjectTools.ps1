#requires -Version 5.1
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'WriteTestManifest.ps1')
$repository = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tool = Join-Path $repository 'Sources/Windows/UdkCli/Tools/ProjectTools/Generate.ps1'
$fixture = Join-Path $repository 'Tests/Fixtures/ProjectTools'
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('ProjectTools.Tests.' + [Guid]::NewGuid().ToString('N'))
try {
    Copy-Item -LiteralPath $fixture -Destination $temporary -Recurse
    $manifest = Join-Path $temporary 'Components.xml'
    $versionPath = Join-Path $temporary '.udk-version'
    [IO.File]::WriteAllText($versionPath, '0.2.0')
    & $tool -ManifestPath $manifest
    if (-not (Test-Path -LiteralPath (Join-Path $temporary 'Projects/Probe/Probe.Dynamic.vcxproj'))) { throw 'Dynamic project was not generated.' }
    $shared = [IO.File]::ReadAllText((Join-Path $temporary 'Projects/Probe/Probe.Shared.vcxitems'))
    if ($shared.Contains('Excluded.cpp') -or -not $shared.Contains('Probe.cpp') -or -not $shared.Contains('Custom.props')) { throw 'Invalid file selection or extension import.' }
    $filtersPath = Join-Path $temporary 'Projects/Probe/Probe.Shared.vcxitems.filters'
    $filters = [IO.File]::ReadAllText($filtersPath)
    if ($filters -notmatch '<ClCompile Include="[^"]*Probe\.cpp" />' -or $filters.Contains('Excluded.cpp')) { throw 'Invalid filter override or source exclusion.' }
    if ($filters -notmatch '<None Include="[^"]*Custom\.props"><Filter>Build</Filter></None>' -or
        $filters -notmatch '<None Include="[^"]*Custom\.targets" />') {
        throw 'Expected the explicit Build filter for Custom.props and the project root for Custom.targets.'
    }
    if ($filters -notmatch '<None Include="[^"]*NewFile\.cpp"><Filter>Examples</Filter></None>') {
        throw 'An explicit File declaration must be displayed without compiling it.'
    }
    $binary = [IO.File]::ReadAllText((Join-Path $temporary 'Projects/Probe/Probe.Static.vcxproj'))
    if (-not $binary.Contains('Custom.targets')) { throw 'Missing target extension.' }
    $solution = Join-Path $temporary 'Probe.sln'
    $before = [IO.File]::ReadAllText($solution)
    if ($before -notmatch '"!Repository"' -or $before -notmatch '\.udk-version = \.udk-version') { throw 'Missing version solution item.' }
    & $tool -ManifestPath $manifest -Check
    & $tool -ManifestPath $manifest
    if ([IO.File]::ReadAllText($solution) -cne $before) { throw 'Repeated generation rewrote the solution.' }
    $nestedSource = New-Item -ItemType Directory -Path (Join-Path $temporary 'Source/Nested')
    Copy-Item -LiteralPath (Join-Path $temporary 'NewFile.cpp') -Destination $nestedSource.FullName
    $rejected = $false
    try { & $tool -ManifestPath $manifest -Check } catch { $rejected = $true }
    if (-not $rejected) { throw 'Check did not detect a new source file.' }
    if ([IO.File]::ReadAllText($solution) -cne $before) { throw 'Check modified the solution.' }
    & $tool -ManifestPath $manifest
    if (-not [IO.File]::ReadAllText((Join-Path $temporary 'Projects/Probe/Probe.Shared.vcxitems')).Contains('NewFile.cpp')) { throw 'New source was not included.' }
    if ([IO.File]::ReadAllText($filtersPath) -notmatch '<ClCompile Include="[^"]*NewFile\.cpp"><Filter>Implementation\\Nested</Filter></ClCompile>') { throw 'Source hierarchy was not preserved.' }
    & $tool -ManifestPath $manifest -Check
    # Removing a variant changes only the managed solution entries; files remain available.
    $componentPath = Join-Path $temporary 'Component.xml'
    $component = Read-UdkManifest $componentPath 'Component'
    $component.variants = @('static')
    [IO.File]::WriteAllText($componentPath, (ConvertTo-TestManifestXml $component 'Component'), [Text.UTF8Encoding]::new($false))
    & $tool -ManifestPath $manifest
    $solutionText = [IO.File]::ReadAllText($solution)
    if ($solutionText.Contains('Probe.Dynamic')) { throw 'Removed variant survived in the solution.' }
    if (-not (Test-Path -LiteralPath (Join-Path $temporary 'Projects/Probe/Probe.Dynamic.vcxproj'))) { throw 'Sync deleted a project file.' }
    $component.variants = @('static', 'dynamic')
    [IO.File]::WriteAllText($componentPath, (ConvertTo-TestManifestXml $component 'Component'), [Text.UTF8Encoding]::new($false))
    & $tool -ManifestPath $manifest
    if (-not [IO.File]::ReadAllText($solution).Contains('Probe.Dynamic')) { throw 'Restored variant was not added.' }
    & $tool -ManifestPath $manifest -Check

    $userFolder = 'Project("{2150E333-8FDC-42A3-9474-1A3956D46DE8}") = "User", "User", "{3CD447C2-9345-4C0C-9F57-9BE45728E021}"' + "`nEndProject`n"
    [IO.File]::WriteAllText($solution, ([IO.File]::ReadAllText($solution) -replace '(?m)^Global\r?$', ($userFolder + 'Global')))
    $dynamicProject = Join-Path $temporary 'Projects/Probe/Probe.Dynamic.vcxproj'
    [IO.File]::WriteAllText(($dynamicProject + '.user'), '<Project />')
    & $tool -ManifestPath $manifest -Clean
    $cleaned = [IO.File]::ReadAllText($solution)
    if ($cleaned -match 'Probe\.(Dynamic|Static|Shared)|\.udk-version|"!Repository"|"Projects"' -or $cleaned -notmatch '"User", "User"') {
        throw 'Cleanup did not preserve the user folder or left generated entries.'
    }
    foreach ($path in @($versionPath, $dynamicProject, ($dynamicProject + '.filters'), ($dynamicProject + '.user'), $filtersPath)) {
        if (Test-Path -LiteralPath $path) { throw "Cleanup left generated file: $path" }
    }
    & $tool -ManifestPath $manifest -Clean
    if ([IO.File]::ReadAllText($solution) -cne $cleaned) { throw 'Repeated cleanup rewrote the solution.' }

    $settings = (Read-UdkManifest $manifest 'ComponentRegistry').generation
    $settings.msbuild.PSObject.Properties.Remove('projectName')
    $settings.msbuild | Add-Member projectNames @(
        @{ when = @{ platform = 'android' }; template = 'Android.{name}' }
        @{ when = @{ artifact = 'sharedItems' }; template = '{name}.Shared' }
        @{ when = @{ artifact = 'project'; variant = @('static', 'dynamic') }; template = '{name}.{variant:title}' }
        @{ when = @{ projectType = 'classLibrary' }; template = 'Root.{name}' }
        @{ template = '{name}' }
    )
    $registry = @{ schemaVersion = 5; components = @('Component.xml'); generation = $settings }
    $utf8 = [Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText($manifest, (ConvertTo-TestManifestXml $registry 'ComponentRegistry'), $utf8)
    $component.PSObject.Properties.Remove('name')
    $component.kind = 'library'
    $component | Add-Member projectType 'native'
    $component | Add-Member id 'native'
    $component | Add-Member msbuild @{ projectNames = @(
        @{ when = @{ artifact = 'project'; kind = 'library'; variant = 'static' }; template = '{name}.Archive' }
    ) }
    $runtime = @{ projectId = 'native'; variant = 'Dynamic' }
    $managed = @{
        kind = 'library'; projectType = 'classLibrary'; sources = @()
        msbuild = @{ projectNames = @(@{ template = '{name}.{framework}' }); properties = @{ TargetFramework = 'net8.0' } }
        runtimeDependencies = @($runtime)
    }
    $description = @{ name = 'Probe'; projects = @($managed, $component) }
    [IO.File]::WriteAllText($componentPath, (ConvertTo-TestManifestXml $description 'Component'), $utf8)
    & $tool -ManifestPath $manifest
    $managedPath = Join-Path $temporary 'Projects/Probe/Probe.net8.0.csproj'
    [xml]$managedProject = Get-Content -LiteralPath $managedPath -Raw
    if (-not (Test-Path -LiteralPath (Join-Path $temporary 'Projects/Probe/Probe.Archive.vcxproj') -PathType Leaf)) {
        throw 'The Static naming rule did not override the component default.'
    }
    $reference = $managedProject.SelectSingleNode('/Project/ItemGroup/ProjectReference')
    if ($reference.Include -cne 'Probe.Dynamic.vcxproj' -or $reference.ReferenceOutputAssembly -cne 'false' -or
        -not [IO.File]::ReadAllText($solution).Contains('"Probe.net8.0", "Projects\Probe\Probe.net8.0.csproj"')) {
        throw 'The solution or runtime reference for the C# library was not generated.'
    }
    & $tool -ManifestPath $manifest -Check
    # Exercise adoption and pruning while preserving a manual item in the same solution folder.
    [xml]$descriptionXml = Get-Content -LiteralPath $componentPath -Raw
    $solutionFiles = $descriptionXml.CreateElement('Files')
    $solutionFiles.InnerXml = '<Group name="Code"><File>Source/**/*.cpp</File></Group>' +
        '<Group name="Build"><Generated>Projects/Probe/*.Archive.vcxproj</Generated></Group>'
    [void]$descriptionXml.DocumentElement.AppendChild($solutionFiles)
    $solutionFilters = $descriptionXml.CreateElement('Filters')
    $solutionFilters.InnerXml = '<Filter filter="{Tree:Solution}/Browse" preserveTree="true"><GroupRef>Code</GroupRef></Filter>' +
        '<Filter filter="{Tree:Solution}/Selected"><Match>**/NewFile.cpp</Match></Filter>' +
        '<Filter filter="{Tree:Solution}/Generated"><GroupRef>Build</GroupRef></Filter>'
    [void]$descriptionXml.DocumentElement.AppendChild($solutionFilters)
    $solutionDescription = $descriptionXml.OuterXml
    [IO.File]::WriteAllText($componentPath, $solutionDescription, $utf8)
    & $tool -ManifestPath $manifest
    $generated = [IO.File]::ReadAllText($solution)
    if (-not $generated.Contains('Projects\Probe\Probe.Archive.vcxproj = Projects\Probe\Probe.Archive.vcxproj') -or
        $generated -match '(?m)^\s*Projects\\Probe\\Probe\.(Dynamic|Static)\.vcxproj = ') {
        throw 'Generated solution items did not select only the requested output.'
    }
    if ($generated -notmatch '"Browse", "Browse"' -or
        $generated -notmatch '(?s)"Selected", "Selected"[^\r\n]*\r?\n\s+ProjectSection\(SolutionItems\) = preProject\s+Source\\Nested\\NewFile\.cpp = Source\\Nested\\NewFile\.cpp' -or
        $generated -match '(?m)^\s*NewFile\.cpp = NewFile\.cpp') {
        throw 'Match must move only files declared in Files.'
    }
    $manualEntry = "`t`tNewFile.cpp = NewFile.cpp"
    $generated = $generated -replace '(?m)^(\t\tSource\\Probe\.cpp = Source\\Probe\.cpp\r?)$', ('${1}' + "`n" + $manualEntry)
    if (-not $generated.Contains($manualEntry)) { throw 'Unable to seed the manual solution item.' }
    [IO.File]::WriteAllText($solution, $generated, $utf8)
    [IO.File]::WriteAllText($componentPath, $solutionDescription.Replace('{Tree:Solution}/Browse', '{Tree:Solution}/Moved'), $utf8)
    & $tool -ManifestPath $manifest
    $moved = [IO.File]::ReadAllText($solution)
    if ($moved -notmatch '"Moved", "Moved"' -or -not $moved.Contains($manualEntry) -or
        [regex]::Matches($moved, '(?m)^\t\tSource\\Probe\.cpp = ').Count -ne 1) {
        throw 'Solution reconciliation lost a manual item or retained a stale entry.'
    }
    & $tool -ManifestPath $manifest -Check
    $runtime.Remove('projectId')
    $runtime.project = 'native'
    [IO.File]::WriteAllText($componentPath, (ConvertTo-TestManifestXml $description 'Component'), $utf8)
    $rejected = $false
    try { & $tool -ManifestPath $manifest -Check } catch { $rejected = $_.Exception.Message -match 'Expected projectId' }
    if (-not $rejected) { throw 'A runtime dependency using project instead of projectId was accepted.' }
    Write-Host 'PASS: standalone generation, variants, glob/exclude, extensions, check and idempotence.'
} finally {
    $resolved = [IO.Path]::GetFullPath($temporary)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'ProjectTools.Tests.*') { throw 'Unexpected temporary test directory.' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}