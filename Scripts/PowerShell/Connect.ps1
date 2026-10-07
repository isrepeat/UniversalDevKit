param(
    [string]$ProjectPath,
    [string[]]$Components,
    [switch]$Disconnect
)

$ErrorActionPreference = 'Stop'
$repositoryPath = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$integrationPath = Join-Path $repositoryPath 'Projects\MsBuild\UniversalDevKit.Sources.targets'

function SelectConsoleItem {
    param([string]$Title, [string[]]$Items)

    if (-not $Items.Count) { throw 'Menu has no items.' }
    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) {
        throw 'Interactive selection requires a console. Use PowerShell parameters for non-interactive execution.'
    }
    $selected = 0
    $previousCursorVisible = [Console]::CursorVisible
    try {
        [Console]::CursorVisible = $false
        while ($true) {
            # Перерисовываем меню целиком, чтобы длинные пути не нарушали положение курсора.
            [Console]::Clear()
            Write-Host $Title
            Write-Host 'Up/Down: select | Enter: confirm | Esc: cancel'
            Write-Host ''
            for ($index = 0; $index -lt $Items.Count; $index++) {
                if ($index -eq $selected) {
                    Write-Host ('> ' + $Items[$index]) -ForegroundColor Cyan
                }
                else { Write-Host ('  ' + $Items[$index]) }
            }
            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                'UpArrow' { $selected = ($selected + $Items.Count - 1) % $Items.Count }
                'DownArrow' { $selected = ($selected + 1) % $Items.Count }
                'Enter' { return $selected }
                'Escape' { throw 'Operation cancelled. No project changes were written.' }
            }
        }
    }
    finally { [Console]::CursorVisible = $previousCursorVisible }
}

if (-not $ProjectPath) {
    $location = (Read-Host 'Path to consumer .vcxproj, .sln or project directory').Trim('"')
    if (Test-Path -LiteralPath $location -PathType Container) {
        $projects = @(Get-ChildItem -LiteralPath $location -Recurse -Filter '*.vcxproj' -File |
            Where-Object { $_.FullName -notmatch '[\\/](!artifacts|build|\.git|\.vs)[\\/]' -and
                -not $_.FullName.StartsWith($repositoryPath + '\', [StringComparison]::OrdinalIgnoreCase) } |
            ForEach-Object FullName | Sort-Object)
    }
    elseif ([IO.Path]::GetExtension($location) -eq '.sln') {
        $solutionPath = (Resolve-Path -LiteralPath $location).Path
        $projects = @(foreach ($line in Get-Content -LiteralPath $solutionPath) {
            if ($line -match '^Project\(.*\)\s*=\s*"[^"]*",\s*"([^"]+\.vcxproj)"') {
                [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $solutionPath) $Matches[1]))
            }
        })
    }
    else { $projects = @($location) }
    if (-not $projects.Count) { throw 'No consumer C++ projects found.' }
    $selection = SelectConsoleItem -Title 'Select consumer project' -Items $projects
    $ProjectPath = $projects[$selection]
    $action = SelectConsoleItem -Title $ProjectPath -Items @('Connect / update', 'Disconnect')
    if ($action -eq 1) { $Disconnect = $true }
    if (-not $Disconnect) {
        $availableComponents = @('Helpers', 'Diagnostic', 'Helpers + Diagnostic')
        $selection = SelectConsoleItem -Title 'Select component' -Items $availableComponents
        $Components = if ($selection -eq 2) { @('Helpers', 'Diagnostic') } else { @($availableComponents[$selection]) }
    }
    [Console]::Clear()
    Write-Host ('Consumer: ' + $ProjectPath)
}
if (-not $Disconnect) {
    if (-not $Components) { $Components = @('Helpers') }
    foreach ($component in $Components) {
        if ($component -cnotin @('Helpers', 'Diagnostic')) { throw "Unsupported component: $component" }
    }
    $Components = @($Components | Select-Object -Unique)
}
$projectFile = (Resolve-Path -LiteralPath $ProjectPath).Path
if ([IO.Path]::GetExtension($projectFile) -ne '.vcxproj') { throw 'Expected .vcxproj file.' }
$original = [IO.File]::ReadAllText($projectFile)
$document = [Xml.XmlDocument]::new()
$document.PreserveWhitespace = $true
$document.LoadXml($original)
$namespace = 'http://schemas.microsoft.com/developer/msbuild/2003'
if ($document.DocumentElement.LocalName -ne 'Project' -or $document.DocumentElement.NamespaceURI -ne $namespace) {
    throw 'Unsupported project XML format.'
}
$newline = if ($original.Contains("`r`n")) { "`r`n" } else { "`n" }
$root = $document.DocumentElement
$owned = @($root.SelectNodes('*[@Label="UniversalDevKit"]'))
# Удаляем только блоки интеграции; соседние настройки проекта сохраняются.
foreach ($node in $owned) {
    $previous = $node.PreviousSibling
    [void]$root.RemoveChild($node)
    if ($previous -and $previous.NodeType -eq [Xml.XmlNodeType]::Whitespace) {
        [void]$root.RemoveChild($previous)
    }
}
if (-not $Disconnect) {
    $projectDirectory = Split-Path -Parent $projectFile
    $baseUri = [Uri]::new($projectDirectory.TrimEnd('\') + '\')
    $relativePath = [Uri]::UnescapeDataString($baseUri.MakeRelativeUri([Uri]::new($integrationPath)).ToString()).Replace('/', '\')
    if ($relativePath -match '^[a-zA-Z]:|^file:') { throw 'Consumer and UniversalDevKit must be on the same drive.' }
    $existing = @($root.SelectNodes('*[local-name()="Import"]') | Where-Object {
        $_.GetAttribute('Project') -match 'UniversalDevKit\.Sources\.targets$'
    })
    if ($existing.Count) { throw 'Unmanaged UniversalDevKit import found; remove it before using Connect.' }
    $group = $document.CreateElement('PropertyGroup', $namespace)
    $group.SetAttribute('Label', 'UniversalDevKit')
    $property = $document.CreateElement('UniversalDevKitComponents', $namespace)
    $property.InnerText = $Components -join ';'
    [void]$group.AppendChild($document.CreateWhitespace($newline + '    '))
    [void]$group.AppendChild($property)
    [void]$group.AppendChild($document.CreateWhitespace($newline + '  '))
    $import = $document.CreateElement('Import', $namespace)
    $import.SetAttribute('Label', 'UniversalDevKit')
    $import.SetAttribute('Project', $relativePath)
    $anchor = $root.LastChild
    if ($anchor -and $anchor.NodeType -eq [Xml.XmlNodeType]::Whitespace) {
        [void]$root.RemoveChild($anchor)
    }
    [void]$root.AppendChild($document.CreateWhitespace($newline + '  '))
    [void]$root.AppendChild($group)
    [void]$root.AppendChild($document.CreateWhitespace($newline + '  '))
    [void]$root.AppendChild($import)
    [void]$root.AppendChild($document.CreateWhitespace($newline))
}
$updated = $document.OuterXml.TrimEnd([char[]]"`r`n")
if ($updated -cne $original) {
    [IO.File]::WriteAllText($projectFile, $updated, [Text.UTF8Encoding]::new($false))
    Write-Host "Updated: $projectFile"
}
else { Write-Host 'Project is already up to date.' }