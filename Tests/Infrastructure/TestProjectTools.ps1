#requires -Version 5.1
param()

$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tool = Join-Path $repository 'Sources/Windows/UdkCli/Tools/ProjectTools/Generate.ps1'
$fixture = Join-Path $repository 'Tests/Fixtures/ProjectTools'
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('ProjectTools.Tests.' + [Guid]::NewGuid().ToString('N'))
try {
    Copy-Item -LiteralPath $fixture -Destination $temporary -Recurse
    $manifest = Join-Path $temporary 'Components.json'
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
        $filters -notmatch '<None Include="[^"]*Custom\.targets"><Filter>Build</Filter></None>') { throw 'Missing Build filters.' }
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
    $componentPath = Join-Path $temporary 'Component.json'
    $component = Get-Content -LiteralPath $componentPath -Raw | ConvertFrom-Json
    $component.variants = @('static')
    [IO.File]::WriteAllText($componentPath, ($component | ConvertTo-Json -Depth 10).TrimEnd([char[]]"`r`n"), [Text.UTF8Encoding]::new($false))
    & $tool -ManifestPath $manifest
    $solutionText = [IO.File]::ReadAllText($solution)
    if ($solutionText.Contains('Probe.Dynamic')) { throw 'Removed variant survived in the solution.' }
    if (-not (Test-Path -LiteralPath (Join-Path $temporary 'Projects/Probe/Probe.Dynamic.vcxproj'))) { throw 'Sync deleted a project file.' }
    $component.variants = @('static', 'dynamic')
    [IO.File]::WriteAllText($componentPath, ($component | ConvertTo-Json -Depth 10).TrimEnd([char[]]"`r`n"), [Text.UTF8Encoding]::new($false))
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

    $settings = (Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json).generation
    $settings.msbuild.PSObject.Properties.Remove('projectName')
    $settings.msbuild | Add-Member projectNames ([pscustomobject]@{ default = '{name}'; DotNet = 'Root.{name}' })
    $registry = @{ schemaVersion = 5; components = @('Component.json'); generation = $settings }
    $utf8 = [Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText($manifest, ($registry | ConvertTo-Json -Depth 10), $utf8)
    $component.PSObject.Properties.Remove('name')
    $component.kind = 'library'
    $component | Add-Member projectType 'native'
    $component | Add-Member id 'native'
    $component | Add-Member msbuild @{ projectNames = @{ default = '{name}.{variant}'; Static = '{name}.Archive' } }
    $runtime = @{ projectId = 'native'; variant = 'Dynamic' }
    $managed = @{
        kind = 'library'; projectType = 'classLibrary'; sources = @()
        msbuild = @{ projectNames = @{ DotNet = '{name}.{framework}' }; properties = @{ TargetFramework = 'net8.0' } }
        runtimeDependencies = @($runtime)
    }
    $description = @{ name = 'Probe'; projects = @($managed, $component) }
    [IO.File]::WriteAllText($componentPath, ($description | ConvertTo-Json -Depth 10), $utf8)
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
    $runtime.Remove('projectId')
    $runtime.project = 'native'
    [IO.File]::WriteAllText($componentPath, ($description | ConvertTo-Json -Depth 10), $utf8)
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