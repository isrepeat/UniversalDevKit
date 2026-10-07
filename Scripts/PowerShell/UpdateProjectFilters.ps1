param(
    [string]$RepositoryRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
)

$ErrorActionPreference = 'Stop'
$repositoryPath = [IO.Path]::GetFullPath($RepositoryRoot)
$prefix = $repositoryPath.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
$updates = [Collections.Generic.List[object]]::new()
$projects = Get-ChildItem -LiteralPath $repositoryPath -Recurse -File |
    Where-Object { $_.Extension -in @('.vcxproj', '.vcxitems') } |
    Where-Object { $_.FullName -notmatch '[\\/](!artifacts|build|\.git|\.vs)[\\/]' } |
    Sort-Object FullName

function EscapeXml([string]$Value) {
    return [Security.SecurityElement]::Escape($Value)
}

foreach ($project in $projects) {
    [xml]$document = Get-Content -LiteralPath $project.FullName -Raw
    $rootNode = $document.SelectSingleNode("/*[local-name()='Project']/*[local-name()='PropertyGroup']/*[local-name()='UniversalDevKitFilterRoots']")
    $filterRoots = if ($rootNode) { @($rootNode.InnerText -split ';' | Where-Object { $_ }) } else { @() }
    $items = @{}
    $filters = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($node in $document.SelectNodes("/*[local-name()='Project']/*[local-name()='ItemGroup']/*[@Include]")) {
        if ($node.LocalName -notin @('ClInclude', 'ClCompile', 'None', 'ResourceCompile', 'CustomBuild', 'Natvis')) {
            continue
        }
        $include = $node.GetAttribute('Include')
        $resolvedInclude = $include.Replace('$(MSBuildThisFileDirectory)', $project.DirectoryName + '\')
        # Сложные пути требуют вычисления MSBuild; не создаём неверное дерево молча.
        if ($resolvedInclude -match '[$@%*?;]') {
            throw "Unsupported Include '$include' in $($project.FullName)"
        }
        $absolute = if ([IO.Path]::IsPathRooted($resolvedInclude)) {
            [IO.Path]::GetFullPath($resolvedInclude)
        } else { [IO.Path]::GetFullPath((Join-Path $project.DirectoryName $resolvedInclude)) }
        if (-not $absolute.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "File outside repository: $absolute"
        }
        $relative = $absolute.Substring($prefix.Length).Replace('/', '\')
        foreach ($filterRoot in $filterRoots) {
            $filterPrefix = $filterRoot.Replace('/', '\').TrimEnd('\') + '\'
            if ($relative.StartsWith($filterPrefix, [StringComparison]::OrdinalIgnoreCase)) {
                $relative = $relative.Substring($filterPrefix.Length)
                break
            }
        }
        if ($node.LocalName -eq 'None') { $relative = 'Build\' + $relative }
        $filter = [IO.Path]::GetDirectoryName($relative)
        $items[$node.LocalName + '|' + $include] = @($node.LocalName, $include, $filter)
        while ($filter) {
            [void]$filters.Add($filter)
            $filter = [IO.Path]::GetDirectoryName($filter)
        }
    }

    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add('<?xml version="1.0" encoding="utf-8"?>')
    $lines.Add('<Project ToolsVersion="4.0" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">')
    $lines.Add('  <ItemGroup>')
    foreach ($filter in ($filters | Sort-Object -CaseSensitive)) {
        $lines.Add('    <Filter Include="' + (EscapeXml $filter) + '" />')
    }
    $lines.Add('  </ItemGroup>')
    $lines.Add('  <ItemGroup>')
    foreach ($key in ($items.Keys | Sort-Object -CaseSensitive)) {
        $item = $items[$key]
        $opening = '    <' + $item[0] + ' Include="' + (EscapeXml $item[1]) + '"'
        if ($item[2]) {
            $lines.Add($opening + '>')
            $lines.Add('      <Filter>' + (EscapeXml $item[2]) + '</Filter>')
            $lines.Add('    </' + $item[0] + '>')
        }
        else {
            $lines.Add($opening + ' />')
        }
    }
    $lines.Add('  </ItemGroup>')
    $lines.Add('</Project>')
    $expected = $lines -join "`n"
    $destination = $project.FullName + '.filters'
    $exists = Test-Path -LiteralPath $destination
    $actual = if ($exists) { [IO.File]::ReadAllText($destination).Replace("`r`n", "`n") } else { '' }
    if ($actual -ceq $expected) { continue }
    $relativeDestination = $destination.Substring($prefix.Length).Replace('\', '/')
    $updates.Add(@{ Path = $destination; Content = $expected; RelativePath = $relativeDestination })
}

# Записываем после проверки всех проектов, без BOM и завершающего перевода строки.
foreach ($update in $updates) {
    [IO.File]::WriteAllText($update.Path, $update.Content, [Text.UTF8Encoding]::new($false))
    Write-Output ('Updated: ' + $update.RelativePath)
}
if (-not $updates.Count) {
    Write-Output 'Project filters are up to date.'
}