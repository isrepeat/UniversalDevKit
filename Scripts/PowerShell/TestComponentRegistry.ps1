$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$fixture = Join-Path $repository 'Tests/RegistryFixture'

# Рассчитываем изменения без записи в fixture или основной репозиторий.
$updates = @(& (Join-Path $PSScriptRoot 'GenerateComponentProjects.ps1') -RepositoryRoot $fixture -PassThru)
$solution = @($updates | Where-Object RelativePath -eq 'UniversalDevKit.sln')
if ($solution.Count -ne 1) {
    throw 'Missing solution update'
}
foreach ($mode in @('Shared', 'Static', 'Dynamic')) {
    if (-not $solution[0].Content.Contains("UniversalDevKit.Example.$mode")) {
        throw "Missing solution project: $mode"
    }
}
$shared = @($updates | Where-Object RelativePath -like '*.Shared.vcxitems')
if ($shared.Count -ne 1 -or -not $shared[0].Content.Contains('UniversalDevKitTargetOS')) {
    throw 'Missing platform selection'
}
[xml]$document = $shared[0].Content
$sources = @($document.SelectNodes('//*[local-name()="ClCompile"]'))
if ($sources.Count -ne 2 -or -not $sources[1].HasAttribute('Condition')) {
    throw 'Invalid platform sources'
}
Write-Output 'New component, solution entries and conditional platform sources passed.'