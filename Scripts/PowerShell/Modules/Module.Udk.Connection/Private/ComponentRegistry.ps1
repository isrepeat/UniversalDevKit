function GetAvailableComponents {
    param([string]$RepositoryPath)
    $integrationPath = Join-Path $RepositoryPath 'Projects/MsBuild/UniversalDevKit.Sources.targets'
    # Реестр компонентов сформирован вместе с графом зависимостей; проверяем его актуальность без записи.
    & (Join-Path $RepositoryPath 'Scripts/PowerShell/GenerateComponentProjects.ps1') -Check | Out-Null
    [xml]$integration = Get-Content -LiteralPath $integrationPath -Raw -Encoding UTF8
    $componentRegistry = $integration.SelectSingleNode("/*[local-name()='Project']/*[local-name()='ItemGroup']/*[local-name()='__UniversalDevKitAvailableComponent']")
    if (-not $componentRegistry) { throw 'UniversalDevKit component registry is missing. Run GenerateComponentProjects.cmd.' }
    return @($componentRegistry.GetAttribute('Include').Split(';'))
}

function Get-UdkComponentRegistry {
    param([string]$RepositoryPath)
    [void](GetAvailableComponents -RepositoryPath $RepositoryPath)
    $manifest = Get-Content -LiteralPath (Join-Path $repositoryPath 'Components.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($manifest.schemaVersion -ne 1 -or -not $manifest.includes) { throw 'Unsupported Components.json schema.' }
    $componentRegistry = @{}
    foreach ($include in $manifest.includes) {
        $component = Get-Content -LiteralPath (Join-Path $repositoryPath $include) -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $component.name -or -not $component.msbuildGuid) { throw "Invalid component description: $include" }
        if ($componentRegistry.ContainsKey($component.name)) { throw "Duplicate component: $($component.name)" }
        $guid = [Guid]::Empty
        if (-not [Guid]::TryParse($component.msbuildGuid, [ref]$guid)) { throw "Invalid component GUID: $($component.name)" }
        $componentRegistry[$component.name] = [pscustomobject]@{
            Name = $component.name
            Guid = $guid
            Dependencies = @($component.dependencies | ForEach-Object {
                [pscustomobject]@{
                    Component = $_.component
                    Visibility = $_.visibility
                    Linkage = $_.linkage
                }
            })
        }
    }
    return $componentRegistry
}

function Resolve-UdkComponents([string[]]$RequestedComponents, $ComponentRegistry) {
    $resolved = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    function AddComponent([string]$Name, [string[]]$Stack) {
        if ($Name -cin $Stack) { throw ('Component dependency cycle: ' + (($Stack + $Name) -join ' -> ')) }
        if (-not $ComponentRegistry.ContainsKey($Name)) { throw "Unknown component dependency: $Name" }
        if (-not $resolved.Add($Name)) { return }
        foreach ($dependency in $ComponentRegistry[$Name].Dependencies) { AddComponent $dependency.Component @($Stack + $Name) }
    }
    foreach ($component in $RequestedComponents) { AddComponent $component @() }
    return @($resolved | Sort-Object)
}