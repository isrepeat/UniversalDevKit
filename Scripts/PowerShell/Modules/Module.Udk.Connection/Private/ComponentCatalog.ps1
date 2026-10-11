function GetAvailableComponents {
    param([string]$RepositoryPath)
    $integrationPath = Join-Path $RepositoryPath 'Projects/MsBuild/UniversalDevKit.Sources.targets'
    # Каталог имён сформирован вместе с графом зависимостей; проверяем его актуальность без записи.
    & (Join-Path $RepositoryPath 'Scripts/PowerShell/GenerateComponentProjects.ps1') -Check | Out-Null
    [xml]$integration = Get-Content -LiteralPath $integrationPath -Raw -Encoding UTF8
    $catalog = $integration.SelectSingleNode("/*[local-name()='Project']/*[local-name()='ItemGroup']/*[local-name()='__UniversalDevKitAvailableComponent']")
    if (-not $catalog) { throw 'UniversalDevKit component catalog is missing. Run GenerateComponentProjects.cmd.' }
    return @($catalog.GetAttribute('Include').Split(';'))
}

function Get-UdkComponentCatalog {
    param([string]$RepositoryPath)
    [void](GetAvailableComponents -RepositoryPath $RepositoryPath)
    $manifest = Get-Content -LiteralPath (Join-Path $repositoryPath 'Components.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($manifest.schemaVersion -ne 1 -or -not $manifest.includes) { throw 'Unsupported Components.json schema.' }
    $catalog = @{}
    foreach ($include in $manifest.includes) {
        $component = Get-Content -LiteralPath (Join-Path $repositoryPath $include) -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $component.name -or -not $component.msbuildGuid) { throw "Invalid component description: $include" }
        if ($catalog.ContainsKey($component.name)) { throw "Duplicate component: $($component.name)" }
        $guid = [Guid]::Empty
        if (-not [Guid]::TryParse($component.msbuildGuid, [ref]$guid)) { throw "Invalid component GUID: $($component.name)" }
        $catalog[$component.name] = [pscustomobject]@{
            Name = $component.name
            Guid = $guid
            Dependencies = @($component.dependencies | ForEach-Object { $_.component })
        }
    }
    return $catalog
}

function Resolve-UdkComponents([string[]]$RequestedComponents, $Catalog) {
    $resolved = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    function AddComponent([string]$Name, [string[]]$Stack) {
        if ($Name -cin $Stack) { throw ('Component dependency cycle: ' + (($Stack + $Name) -join ' -> ')) }
        if (-not $Catalog.ContainsKey($Name)) { throw "Unknown component dependency: $Name" }
        if (-not $resolved.Add($Name)) { return }
        foreach ($dependency in $Catalog[$Name].Dependencies) { AddComponent $dependency @($Stack + $Name) }
    }
    foreach ($component in $RequestedComponents) { AddComponent $component @() }
    return @($resolved | Sort-Object)
}