function GetConnectedComponents([string]$Path) {
    [xml]$project = [IO.File]::ReadAllText($Path)
    $property = $project.SelectSingleNode('/*[local-name()="Project"]/*[local-name()="PropertyGroup" and @Label="UniversalDevKit"]/*[local-name()="UniversalDevKitComponents"]')
    if ($property) {
        return @($property.InnerText.Split(';') | Where-Object { $_ } | Select-Object -Unique)
    }
    return @()
}
function Get-UdkConnectionState {
    param([string]$ProjectPath)

    $components = @(GetConnectedComponents $ProjectPath)
    [xml]$project = [IO.File]::ReadAllText($ProjectPath)
    $modes = @{}
    foreach ($name in $components) {
        $node = $project.SelectSingleNode('/*[local-name()="Project"]/*[local-name()="PropertyGroup" and @Label="UniversalDevKit"]/*[local-name()="UniversalDevKit' + $name + 'Linkage"]')
        $modes[$name] = if ($node) {
            $node.InnerText
        } else {
            'Shared'
        }
    }
    return [pscustomobject]@{ Components = $components; Modes = $modes }
}