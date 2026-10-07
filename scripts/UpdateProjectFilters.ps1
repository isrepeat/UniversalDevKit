param(
    [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot),
    [switch]$Check
)

$ErrorActionPreference = 'Stop'
$repositoryPath = [IO.Path]::GetFullPath($RepositoryRoot)
$prefix = $repositoryPath.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
$patches = [Collections.Generic.List[string]]::new()
$outdated = [Collections.Generic.List[string]]::new()
$projects = Get-ChildItem -LiteralPath $repositoryPath -Filter '*.vcxproj' -Recurse -File |
    Where-Object { $_.FullName -notmatch '[\\/](build|\.git|\.vs)[\\/]' } |
    Sort-Object FullName

function EscapeXml([string]$Value) {
    return [Security.SecurityElement]::Escape($Value)
}

foreach ($project in $projects) {
    [xml]$document = Get-Content -LiteralPath $project.FullName -Raw
    $items = @{}
    $filters = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($node in $document.SelectNodes("/*[local-name()='Project']/*[local-name()='ItemGroup']/*[@Include]")) {
        if ($node.LocalName -notin @('ClInclude', 'ClCompile', 'None', 'ResourceCompile', 'CustomBuild', 'Natvis')) {
            continue
        }
        $include = $node.GetAttribute('Include')
        # Сложные пути требуют вычисления MSBuild; не создаём неверное дерево молча.
        if ($include -match '[$@%*?;]') {
            throw "Unsupported Include '$include' in $($project.FullName)"
        }
        $absolute = [IO.Path]::GetFullPath((Join-Path $project.DirectoryName $include))
        if (-not $absolute.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "File outside repository: $absolute"
        }
        $relative = $absolute.Substring($prefix.Length).Replace('/', '\')
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
    $outdated.Add($relativeDestination)
    if ($exists) {
        $patches.Add('*** Update File: ' + $relativeDestination)
        $patches.Add('@@')
        foreach ($line in ($actual -split "`n")) { $patches.Add('-' + $line) }
    }
    else {
        $patches.Add('*** Add File: ' + $relativeDestination)
    }
    foreach ($line in $lines) { $patches.Add('+' + $line) }
}

if ($Check) {
    if ($outdated.Count) {
        throw ('Outdated project filters: ' + ($outdated -join ', '))
    }
    Write-Output 'Project filters are up to date.'
}
elseif ($patches.Count) {
    # Изменения применяются через apply_patch согласно правилам репозитория.
    Write-Output '*** Begin Patch'
    $patches | Write-Output
    Write-Output '*** End Patch'
}