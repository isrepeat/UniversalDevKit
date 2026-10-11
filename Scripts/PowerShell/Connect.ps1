param(
    [string]$ProjectPath,
    [string[]]$Components,
    [string]$SolutionPath,
    [string]$SolutionInjectorPath,
    [switch]$ProjectOnly,
    [switch]$Disconnect
)

$ErrorActionPreference = 'Stop'
$repositoryPath = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$integrationPath = Join-Path $repositoryPath 'Projects\MsBuild\UniversalDevKit.Sources.targets'
$sharedReferencesCondition = '''$(__IsUniversalDevKitSharedReferences)'' == ''true'''

function GetAvailableComponents {
    # Каталог имён сформирован вместе с графом зависимостей; проверяем его актуальность без записи.
    & (Join-Path $PSScriptRoot 'GenerateComponentProjects.ps1') -Check | Out-Host
    [xml]$integration = Get-Content -LiteralPath $integrationPath -Raw -Encoding UTF8
    $catalog = $integration.SelectSingleNode("/*[local-name()='Project']/*[local-name()='ItemGroup']/*[local-name()='__UniversalDevKitAvailableComponent']")
    if (-not $catalog) { throw 'UniversalDevKit component catalog is missing. Run GenerateComponentProjects.cmd.' }
    return @($catalog.GetAttribute('Include').Split(';'))
}

function GetComponentCatalog {
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

function GetResolvedComponents([string[]]$RequestedComponents, $Catalog) {
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

function GetRelativePath([string]$FromDirectory, [string]$ToPath) {
    if ([IO.Path]::GetPathRoot($FromDirectory) -ne [IO.Path]::GetPathRoot($ToPath)) {
        throw 'Consumer project and UniversalDevKit must be on the same drive.'
    }
    $baseUri = [Uri]::new($FromDirectory.TrimEnd('\') + '\')
    return [Uri]::UnescapeDataString($baseUri.MakeRelativeUri([Uri]::new($ToPath)).ToString()).Replace('/', '\')
}

function GetSolutionSharedProjects([string]$Path) {
    $solutionDirectory = Split-Path -Parent $Path
    $result = @{}
    $pattern = '(?m)^Project\("[^\r\n]+"\)\s*=\s*"UniversalDevKit\.([A-Z][A-Za-z0-9]*)\.Shared",\s*"([^"]+\.vcxitems)",\s*"\{([^}]+)\}"'
    foreach ($match in [regex]::Matches([IO.File]::ReadAllText($Path), $pattern)) {
        $guid = [Guid]::Empty
        if (-not [Guid]::TryParse($match.Groups[3].Value, [ref]$guid)) { throw 'Invalid Shared-project GUID in solution.' }
        $componentPath = [IO.Path]::GetFullPath((Join-Path $solutionDirectory $match.Groups[2].Value))
        $result[$match.Groups[1].Value] = [pscustomobject]@{
            Name = $match.Groups[1].Value
            Guid = $guid
            SolutionRelativePath = $match.Groups[2].Value
            Path = $componentPath
        }
    }
    return $result
}

function UpdateSolutionSharedReferences([string]$Path, [Guid]$ConsumerGuid, $RemoveProjects, $AddProjects) {
    $original = [IO.File]::ReadAllText($Path)
    $newline = if ($original.Contains("`r`n")) { "`r`n" } else { "`n" }
    $consumerKey = $ConsumerGuid.ToString().ToLowerInvariant()
    $lines = [Collections.Generic.List[string]]::new()
    foreach ($project in $AddProjects) {
        $lines.Add($project.SolutionRelativePath + '*{' + $consumerKey + '}*SharedItemsImports = 4')
    }
    $sectionPattern = '(?ms)^(\tGlobalSection\(SharedMSBuildProjectFiles\) = preSolution\r?\n)(.*?)(^\tEndGlobalSection)'
    if (-not [regex]::IsMatch($original, $sectionPattern)) {
        if (-not $AddProjects.Count) { return }
        $section = "`tGlobalSection(SharedMSBuildProjectFiles) = preSolution$newline"
        $section += (($lines | ForEach-Object { "`t`t$_$newline" }) -join '')
        $section += "`tEndGlobalSection$newline"
        $updated = $original -replace '(?m)^EndGlobal$', ($section + 'EndGlobal')
    }
    else {
        $updated = [regex]::Replace($original, $sectionPattern, {
            param($match)
            $content = $match.Groups[2].Value
            # Переводим прежние записи Connect с двумя GUID в стандартный формат MSBuild.
            foreach ($project in (GetSolutionSharedProjects $Path).Values) {
                $legacyPrefix = [regex]::Escape($project.SolutionRelativePath + '*{' + $project.Guid.ToString().ToLowerInvariant() + '}*')
                $replacement = $project.SolutionRelativePath + '*'
                $content = [regex]::Replace($content, "(?im)^\t\t$legacyPrefix(?=\{[^}]+\}\*SharedItemsImports)", {
                    param($legacyMatch)
                    return "`t`t$replacement"
                })
            }
            foreach ($project in $RemoveProjects) {
                $prefix = [regex]::Escape($project.SolutionRelativePath + '*{' + $consumerKey + '}*SharedItemsImports = ')
                $content = [regex]::Replace($content, "(?m)^\t\t$prefix\d+\r?\n?", '')
            }
            if ($AddProjects.Count) {
                $content += (($lines | ForEach-Object { "`t`t$_$newline" }) -join '')
            }
            return $match.Groups[1].Value + $content + $match.Groups[3].Value
        })
    }
    $updated = $updated.TrimEnd([char[]]"`r`n")
    if ($updated -cne $original) {
        [IO.File]::WriteAllText($Path, $updated, [Text.UTF8Encoding]::new($false))
        Write-Host "Updated: $Path"
    }
}

function RemoveSolutionBuildItems([string]$Path) {
    $original = [IO.File]::ReadAllText($Path)
    # Убираем только служебные элементы импортированной папки MsBuild, не сборочные imports.
    $pattern = '(?ms)^Project\("\{2150E333-8FDC-42A3-9474-1A3956D46DE8\}"\) = "MsBuild", "MsBuild", "\{08C8E2C8-A0AA-45C3-8A74-95F9EBF9AD83\}"\r?\n.*?^EndProject'
    $updated = [regex]::Replace($original, $pattern, {
        param($match)
        $block = [regex]::Replace($match.Value,
            '(?m)^\t\tProjects\\MsBuild\\(?:BuildLayout\.props|UniversalDevKit\.props|UniversalDevKit\.Sources\.targets) = [^\r\n]+\r?\n', '')
        return [regex]::Replace($block, '(?m)^\tProjectSection\(SolutionItems\) = preProject\r?\n\tEndProjectSection\r?\n', '')
    })
    if ($updated -cne $original) {
        [IO.File]::WriteAllText($Path, $updated.TrimEnd([char[]]"`r`n"), [Text.UTF8Encoding]::new($false))
    }
}

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

function SelectConsoleComponents {
    param([string]$Title, [string[]]$Items)

    if (-not $Items.Count) { throw 'No components available for this operation.' }
    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) {
        throw 'Interactive selection requires a console. Specify Components for non-interactive execution.'
    }
    $marked = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $selected = 0
    $previousCursorVisible = [Console]::CursorVisible
    try {
        [Console]::CursorVisible = $false
        while ($true) {
            [Console]::Clear()
            Write-Host $Title
            Write-Host 'Up/Down: navigate | Space: toggle | Enter on Apply: confirm | Esc: cancel'
            Write-Host ''
            for ($index = 0; $index -le $Items.Count; $index++) {
                $text = if ($index -eq $Items.Count) { 'Apply' } else {
                    $check = if ($marked.Contains($Items[$index])) { 'x' } else { ' ' }
                    "[$check] " + $Items[$index]
                }
                if ($index -eq $selected) { Write-Host ("> $text") -ForegroundColor Cyan }
                else { Write-Host ("  $text") }
            }
            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                'UpArrow' { $selected = ($selected + $Items.Count) % ($Items.Count + 1) }
                'DownArrow' { $selected = ($selected + 1) % ($Items.Count + 1) }
                'Spacebar' {
                    if ($selected -lt $Items.Count) {
                        if (-not $marked.Remove($Items[$selected])) { [void]$marked.Add($Items[$selected]) }
                    }
                }
                'Enter' {
                    if ($selected -eq $Items.Count -and $marked.Count) {
                        return @($Items | Where-Object { $marked.Contains($_) })
                    }
                }
                'Escape' { throw 'Operation cancelled. No project changes were written.' }
            }
        }
    }
    finally { [Console]::CursorVisible = $previousCursorVisible }
}

function GetConnectedComponents([string]$Path) {
    [xml]$project = [IO.File]::ReadAllText($Path)
    $property = $project.SelectSingleNode('/*[local-name()="Project"]/*[local-name()="PropertyGroup" and @Label="UniversalDevKit"]/*[local-name()="UniversalDevKitComponents"]')
    if ($property) {
        return @($property.InnerText.Split(';') | Where-Object { $_ } | Select-Object -Unique)
    }
    return @()
}

$interactive = -not $Components -and -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected
if ($ProjectOnly) {
    if ($SolutionPath) { throw 'ProjectOnly cannot be combined with SolutionPath.' }
    if (-not $ProjectPath) { $ProjectPath = (Read-Host 'Path to consumer .vcxproj').Trim('"') }
}
else {
    # Обычный сценарий начинается с решения; consumer выбирается только из его проектов.
    if (-not $SolutionPath) {
        if ([Console]::IsInputRedirected) { throw 'Specify SolutionPath for Shared References, or ProjectOnly for a standalone project.' }
        $SolutionPath = (Read-Host 'Path to consumer .sln or solution directory').Trim('"')
    }
    $targetSolution = (Resolve-Path -LiteralPath $SolutionPath).Path
    if (Test-Path -LiteralPath $targetSolution -PathType Container) {
        # Ищем решения непосредственно в выбранной папке, без артефактов из подкаталогов.
        $solutions = @(Get-ChildItem -LiteralPath $targetSolution -Filter '*.sln' -File | Sort-Object Name | ForEach-Object FullName)
        if (-not $solutions.Count) { throw "No .sln files found in directory: $targetSolution" }
        $targetSolution = $solutions[(SelectConsoleItem -Title 'Select consumer solution' -Items $solutions)]
    }
    $SolutionPath = $targetSolution
    if ([IO.Path]::GetExtension($targetSolution) -ne '.sln') { throw 'Expected target .sln file.' }
    $projects = @(@(foreach ($line in Get-Content -LiteralPath $targetSolution) {
        if ($line -match '^Project\(.*\)\s*=\s*"[^"]*",\s*"([^"]+\.vcxproj)"') {
            $candidate = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $targetSolution) $Matches[1]))
            # Проекты самой библиотеки не являются потребителями.
            if (-not $candidate.StartsWith($repositoryPath + '\', [StringComparison]::OrdinalIgnoreCase)) { $candidate }
        }
    }) | Sort-Object -Unique)
    if (-not $projects.Count) { throw 'No consumer C++ projects found in solution.' }
    if ($ProjectPath) {
        $ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
        if ($ProjectPath -notin $projects) { throw 'Selected consumer project is not part of the target solution.' }
    }
    elseif ($projects.Count -eq 1) { $ProjectPath = $projects[0] }
    else { $ProjectPath = $projects[(SelectConsoleItem -Title 'Select consumer project' -Items $projects)] }
}
if ($interactive -and -not $Disconnect) {
    $action = SelectConsoleItem -Title $ProjectPath -Items @('Connect / update', 'Disconnect')
    if ($action -eq 1) { $Disconnect = $true }
}

# 1. Выбираем явные компоненты; автоматически раскрытые зависимости отдельно не отключаются.
$connectedComponents = @(GetConnectedComponents $ProjectPath)
if ($interactive -and -not $Components) {
    if ($Disconnect -and -not $connectedComponents.Count) {
        Write-Host 'No UniversalDevKit components are connected to this project.'
        return
    }
    $menuItems = if ($Disconnect) { $connectedComponents } else { @(GetAvailableComponents) }
    $title = if ($Disconnect) { 'Select components to disconnect' } else { 'Select components to connect' }
    $Components = @(SelectConsoleComponents -Title $title -Items $menuItems)
    [Console]::Clear()
    Write-Host ('Consumer: ' + $ProjectPath)
}

# 2. Получаем итоговый набор корней, сохраняя компоненты, не выбранные для удаления.
$cleanupRequested = [bool]$Disconnect
if ($cleanupRequested) {
    if ($Components) {
        foreach ($component in $Components) {
            if ($component -cnotin $connectedComponents) { throw "Component is not explicitly connected: $component" }
        }
        $componentsToRemove = @($Components)
        $Components = @($connectedComponents | Where-Object { $_ -cnotin $componentsToRemove })
    }
    else { $Components = @() }
    $Disconnect = -not $Components.Count
}
else {
    $Components = @(@($connectedComponents) + @($Components) | Select-Object -Unique)
}

# 3. Для оставшихся корней обычная интеграция заново раскрывает зависимости.
if ($SolutionPath) {
    $solutionInjector = & (Join-Path $PSScriptRoot 'GetSolutionInjector.ps1') -LocalPath $SolutionInjectorPath
}
if (-not $Disconnect) {
    if (-not $availableComponents) { $availableComponents = @(GetAvailableComponents) }
    if (-not $Components) {
        $Components = if ('Helpers' -cin $availableComponents) { @('Helpers') } else { @($availableComponents[0]) }
    }
    foreach ($component in $Components) {
        if ($component -cnotin $availableComponents) { throw "Unsupported component: $component" }
    }
    $Components = @($Components | Select-Object -Unique)
    $componentCatalog = GetComponentCatalog
    $resolvedComponents = @(GetResolvedComponents $Components $componentCatalog)
}
$projectFile = (Resolve-Path -LiteralPath $ProjectPath).Path
if ([IO.Path]::GetExtension($projectFile) -ne '.vcxproj') { throw 'Expected .vcxproj file.' }
$projectDirectory = Split-Path -Parent $projectFile
$original = [IO.File]::ReadAllText($projectFile)
$document = [Xml.XmlDocument]::new()
$document.PreserveWhitespace = $true
$document.LoadXml($original)
$namespace = 'http://schemas.microsoft.com/developer/msbuild/2003'
if ($document.DocumentElement.LocalName -ne 'Project' -or $document.DocumentElement.NamespaceURI -ne $namespace) {
    throw 'Unsupported project XML format.'
}
$projectGuidNode = $document.SelectSingleNode('/*[local-name()="Project"]/*[local-name()="PropertyGroup"]/*[local-name()="ProjectGuid"]')
$consumerGuid = [Guid]::Empty
if (-not $projectGuidNode -or -not [Guid]::TryParse($projectGuidNode.InnerText, [ref]$consumerGuid)) {
    throw 'Consumer project must contain a valid ProjectGuid.'
}
$newline = if ($original.Contains("`r`n")) { "`r`n" } else { "`n" }
$root = $document.DocumentElement
$sharedProjects = @()
$previousSharedProjects = @()
if ($SolutionPath) {
    $sourceSolution = Join-Path $repositoryPath 'UniversalDevKit.sln'
    if (-not $Disconnect) {
        # Повторная вставка восстанавливает удалённые очисткой компоненты без дублирования оставшихся.
        & $solutionInjector $sourceSolution $targetSolution --rootName UniversalDevKit -f MsBuild
        if ($LASTEXITCODE -ne 0) { throw "SolutionInjector failed with exit code $LASTEXITCODE." }
    }
    if (-not $Disconnect) { RemoveSolutionBuildItems $targetSolution }
    $solutionSharedProjects = GetSolutionSharedProjects $targetSolution
    $previousSharedPaths = @($root.SelectNodes('*[local-name()="ImportGroup" and @Label="Shared" and @Condition="' + $sharedReferencesCondition + '"]/*[local-name()="Import"]') |
        ForEach-Object {
            [IO.Path]::GetFullPath((Join-Path $projectDirectory $_.GetAttribute('Project')))
        })
    $previousSharedProjects = @($solutionSharedProjects.Values | Where-Object { $_.Path -in $previousSharedPaths })
    if (-not $Disconnect) {
        foreach ($component in $resolvedComponents) {
            if (-not $solutionSharedProjects.ContainsKey($component)) {
                throw "Shared project is missing from solution: UniversalDevKit.$component.Shared"
            }
            $sharedProjects += $solutionSharedProjects[$component]
        }
    }
}
$owned = @($root.SelectNodes('*[@Label="UniversalDevKit"]'))
$owned += @($root.SelectNodes('*[local-name()="ImportGroup" and @Label="Shared" and @Condition="' + $sharedReferencesCondition + '"]'))
# Удаляем только блоки интеграции; соседние настройки проекта сохраняются.
foreach ($node in $owned) {
    $previous = $node.PreviousSibling
    [void]$root.RemoveChild($node)
    if ($previous -and $previous.NodeType -eq [Xml.XmlNodeType]::Whitespace) {
        [void]$root.RemoveChild($previous)
    }
}
if (-not $Disconnect) {
    $relativePath = GetRelativePath $projectDirectory $integrationPath
    $existing = @($root.SelectNodes('*[local-name()="Import"]') | Where-Object {
        $_.GetAttribute('Project') -match 'UniversalDevKit\.Sources\.targets$'
    })
    if ($existing.Count -and $SolutionPath) { throw 'Unmanaged UniversalDevKit Sources.targets import found; remove it before using Shared References.' }
    if ($existing.Count -and -not $SolutionPath) { throw 'Unmanaged UniversalDevKit import found; remove it before using Connect.' }
    $group = $document.CreateElement('PropertyGroup', $namespace)
    $group.SetAttribute('Label', 'UniversalDevKit')
    $property = $document.CreateElement('UniversalDevKitComponents', $namespace)
    $property.InnerText = $Components -join ';'
    [void]$group.AppendChild($document.CreateWhitespace($newline + '    '))
    [void]$group.AppendChild($property)
    if ($SolutionPath) {
        $sharedProperty = $document.CreateElement('__IsUniversalDevKitSharedReferences', $namespace)
        $sharedProperty.InnerText = 'true'
        [void]$group.AppendChild($document.CreateWhitespace($newline + '    '))
        [void]$group.AppendChild($sharedProperty)
    }
    [void]$group.AppendChild($document.CreateWhitespace($newline + '  '))
    $anchor = $root.SelectSingleNode('*[local-name()="Import" and contains(@Project, "Microsoft.Cpp.targets")]')
    if (-not $anchor) { throw 'Microsoft.Cpp.targets import not found.' }
    [void]$root.InsertBefore($document.CreateWhitespace($newline + '  '), $anchor)
    [void]$root.InsertBefore($group, $anchor)
    if ($SolutionPath) {
        $sharedGroup = $document.CreateElement('ImportGroup', $namespace)
        $sharedGroup.SetAttribute('Label', 'Shared')
        $sharedGroup.SetAttribute('Condition', $sharedReferencesCondition)
        foreach ($sharedProject in $sharedProjects) {
            $sharedImport = $document.CreateElement('Import', $namespace)
            $sharedImport.SetAttribute('Label', 'Shared')
            $sharedImport.SetAttribute('Project', (GetRelativePath $projectDirectory $sharedProject.Path))
            [void]$sharedGroup.AppendChild($document.CreateWhitespace($newline + '    '))
            [void]$sharedGroup.AppendChild($sharedImport)
        }
        [void]$sharedGroup.AppendChild($document.CreateWhitespace($newline + '  '))
        [void]$root.InsertBefore($document.CreateWhitespace($newline + '  '), $anchor)
        [void]$root.InsertBefore($sharedGroup, $anchor)
        [void]$root.InsertBefore($document.CreateWhitespace($newline + '  '), $anchor)
    }
    else {
        $import = $document.CreateElement('Import', $namespace)
        $import.SetAttribute('Label', 'UniversalDevKit')
        $import.SetAttribute('Project', $relativePath)
        [void]$root.InsertBefore($document.CreateWhitespace($newline + '  '), $anchor)
        [void]$root.InsertBefore($import, $anchor)
        [void]$root.InsertBefore($document.CreateWhitespace($newline + '  '), $anchor)
    }
}
$updated = $document.OuterXml.TrimEnd([char[]]"`r`n")
if ($updated -cne $original) {
    [IO.File]::WriteAllText($projectFile, $updated, [Text.UTF8Encoding]::new($false))
    Write-Host "Updated: $projectFile"
}
else { Write-Host 'Project is already up to date.' }

if ($SolutionPath) {
    $referencesToRemove = @($previousSharedProjects + $sharedProjects | Sort-Object Guid -Unique)
    $referencesToAdd = if ($Disconnect) { @() } else { $sharedProjects }
    UpdateSolutionSharedReferences $targetSolution $consumerGuid $referencesToRemove $referencesToAdd

    if ($cleanupRequested) {
        # 1. Ищем корневую папку по типу и имени; повторное отключение без дерева ничего не меняет.
        $content = [IO.File]::ReadAllText($targetSolution)
        $scopePattern = '(?m)^Project\("\{2150E333-8FDC-42A3-9474-1A3956D46DE8\}"\)\s*=\s*"UniversalDevKit",\s*"[^"]+",\s*"\{([^}]+)\}"'
        $scopes = [regex]::Matches($content, $scopePattern)
        if ($scopes.Count -gt 1) { throw 'Ambiguous UniversalDevKit scope; automatic cleanup was not applied.' }
        if ($scopes.Count -eq 1) {
            # 2. Рассчитываем и применяем очистку после записи всех связей consumer.
            # SolutionInjector сохраняет используемые другими проектами зависимости и резервную копию .sln.
            $scopeGuid = '{' + $scopes[0].Groups[1].Value + '}'
            $cleanupOutput = & $solutionInjector prune $targetSolution --scope $scopeGuid --apply --json
            $cleanupExitCode = $LASTEXITCODE
            if ($cleanupExitCode -notin @(0, 2)) {
                throw "Consumer was disconnected, but solution cleanup failed with exit code $cleanupExitCode."
            }
            $cleanupReport = ($cleanupOutput -join "`n") | ConvertFrom-Json
            if ($cleanupReport.schemaVersion -ne 1) { throw 'Unsupported SolutionInjector cleanup report version.' }

            # 3. При неоднозначном анализе оставляем дерево решения и показываем причины.
            if ($cleanupExitCode -eq 2 -or $cleanupReport.blocked) {
                foreach ($issue in $cleanupReport.issues) { Write-Warning "Cleanup skipped: $issue" }
                Write-Warning 'Consumer was disconnected; solution projects were retained because dependency analysis was blocked.'
            }
            elseif (-not $cleanupReport.applied) { throw 'SolutionInjector did not apply the cleanup plan.' }
            else {
                Write-Host ('Cleanup: removed {0} projects and {1} folders.' -f @($cleanupReport.removedProjects).Count, @($cleanupReport.removedFolders).Count)
            }
        }
    }
}