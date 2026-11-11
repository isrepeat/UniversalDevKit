#requires -Version 7.0
param()

$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tool = Join-Path $repository 'Sources/Windows/UdkCli/Tools/ProjectTools/Generate.ps1'
$fixture = Join-Path $repository 'Tests/Fixtures/ProjectTools'
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('ProjectTools.Tests.' + [Guid]::NewGuid().ToString('N'))
try {
    Copy-Item -LiteralPath $fixture -Destination $temporary -Recurse
    $manifest = Join-Path $temporary 'Components.json'
    & $tool -ManifestPath $manifest
    if (-not (Test-Path -LiteralPath (Join-Path $temporary 'Projects/Probe/Probe.Dynamic.vcxproj'))) { throw 'Dynamic project was not generated.' }
    $shared = [IO.File]::ReadAllText((Join-Path $temporary 'Projects/Probe/Probe.Shared.vcxitems'))
    if ($shared.Contains('Excluded.cpp') -or -not $shared.Contains('Probe.cpp') -or -not $shared.Contains('Custom.props')) { throw 'Invalid file selection or extension import.' }
    $binary = [IO.File]::ReadAllText((Join-Path $temporary 'Projects/Probe/Probe.Static.vcxproj'))
    if (-not $binary.Contains('Custom.targets')) { throw 'Missing target extension.' }
    $solution = Join-Path $temporary 'Probe.sln'
    $before = [IO.File]::ReadAllText($solution)
    & $tool -ManifestPath $manifest -Check
    & $tool -ManifestPath $manifest
    if ([IO.File]::ReadAllText($solution) -cne $before) { throw 'Repeated generation rewrote the solution.' }
    Copy-Item -LiteralPath (Join-Path $temporary 'NewFile.cpp') -Destination (Join-Path $temporary 'Source/NewFile.cpp')
    $rejected = $false
    try { & $tool -ManifestPath $manifest -Check } catch { $rejected = $true }
    if (-not $rejected) { throw 'Check did not detect a new source file.' }
    if ([IO.File]::ReadAllText($solution) -cne $before) { throw 'Check modified the solution.' }
    & $tool -ManifestPath $manifest
    if (-not [IO.File]::ReadAllText((Join-Path $temporary 'Projects/Probe/Probe.Shared.vcxitems')).Contains('NewFile.cpp')) { throw 'New source was not included.' }
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
    Write-Host 'PASS: standalone generation, variants, glob/exclude, extensions, check and idempotence.'
} finally {
    $resolved = [IO.Path]::GetFullPath($temporary)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'ProjectTools.Tests.*') { throw 'Unexpected temporary test directory.' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}