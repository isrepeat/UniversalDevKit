$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$fixture = Join-Path $repository 'Tests/Fixtures/Libraries/Registry'

# Calculate changes without writing to the fixture or the main repository.
$updates = @(& (Join-Path $repository 'Scripts/PowerShell/GenerateComponentProjects.ps1') -RepositoryRoot $fixture -PassThru)
$solution = @($updates | Where-Object RelativePath -eq 'UniversalDevKit.sln')
if ($solution.Count -ne 1) {
    throw 'Missing solution update'
}
foreach ($mode in @('Shared', 'Static', 'Dynamic')) {
    if (-not $solution[0].Content.Contains("UniversalDevKit.Example.$mode")) {
        throw "Missing solution project: $mode"
    }
}
$shared = @($updates | Where-Object RelativePath -like '*Example.Shared.vcxitems')
if ($shared.Count -ne 1 -or -not $shared[0].Content.Contains('UniversalDevKitTargetOS')) {
    throw 'Missing platform selection'
}
[xml]$document = $shared[0].Content
$sources = @($document.SelectNodes('//*[local-name()="ClCompile" and @Include]'))
if ($sources.Count -ne 2 -or -not $sources[1].HasAttribute('Condition')) {
    throw 'Invalid platform sources'
}
Write-Output 'New component, solution entries and conditional platform sources passed.'

if (@($updates | Where-Object RelativePath -like '*Service.Static.vcxproj').Count) {
    throw 'Process-state Static project was generated'
}
if ($solution[0].Content.Contains('UniversalDevKit.Service.Shared') -or $solution[0].Content.Contains('UniversalDevKit.Service.Static')) {
    throw 'Forbidden process-state projects were added to solution'
}
$sourceTargets = @($updates | Where-Object RelativePath -eq 'Projects/MsBuild/UniversalDevKit.Sources.targets')[0].Content
if (-not $sourceTargets.Contains('Service.Dynamic.vcxproj') -or -not $sourceTargets.Contains('UNIVERSALDEVKIT_SERVICE_DYNAMIC')) {
    throw 'Shared-to-Dynamic dependency is missing from ProjectOnly targets'
}

if (-not $shared[0].Content.Contains('<MinimumStandard>20</MinimumStandard>') -or -not $shared[0].Content.Contains('ws2_32.lib')) {
    throw 'Common requirements were not emitted for Shared'
}
$staticProject = @($updates | Where-Object RelativePath -like '*Example.Static.vcxproj')[0].Content
if (-not $staticProject.Contains('<LanguageStandard>stdcpp20</LanguageStandard>')) {
    throw 'New library project did not select the required standard'
}
. (Join-Path $repository 'Scripts/PowerShell/Modules/Module.Udk.Connection/Private/Requirements.ps1')
foreach ($json in @('{"requirements":{"unknown":true}}', '{"requirements":{"cxxStandard":16}}', '{"requirements":{"threads":"true"}}')) {
    $rejected = $false
    try {
        Get-UdkRequirementDefinition ($json | ConvertFrom-Json) | Out-Null
    } catch {
        $rejected = $true
    }
    if (-not $rejected) {
        throw "Invalid requirement was accepted: $json"
    }
}