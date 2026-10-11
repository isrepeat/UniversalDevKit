param(
    [string]$ProjectPath,
    [string[]]$Components,
    [hashtable]$ComponentModes = @{},
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
    & (Join-Path $PSScriptRoot 'GenerateComponentProjects.ps1') -Check | ForEach-Object { WriteMenuText $_ Hint }
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
        WriteMenuText "Updated: $Path" Mark
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

function WriteMenuText {
    param([string]$Text, [string]$Role = 'Text', [switch]$NoNewline)

    # RGB-палитра Olive; для консоли без ANSI используем ближайшие стандартные цвета.
    $palette = @{
        Title = @{ Rgb = '166;185;129'; Fallback = 'DarkGreen' }
        Text = @{ Rgb = '170;170;170'; Fallback = 'Gray' }
        Hint = @{ Rgb = '119;119;119'; Fallback = 'DarkGray' }
        Mark = @{ Rgb = '180;204;149'; Fallback = 'Green' }
        Focus = @{ Rgb = '216;196;120'; Fallback = 'Yellow' }
    }
    $color = $palette[$Role]
    if ($Host.UI.SupportsVirtualTerminal -and -not [Console]::IsOutputRedirected) {
        $escape = [char]27
        $background = if ($Role -eq 'Focus') { "$escape[48;2;36;39;31m" } else { '' }
        Write-Host ("$escape[38;2;$($color.Rgb)m$background$Text$escape[0m") -NoNewline:$NoNewline
    }
    else { Write-Host $Text -ForegroundColor $color.Fallback -NoNewline:$NoNewline }
}

function ReadMenuPath([string]$Prompt) {
    WriteMenuText ($Prompt + ': ') Title -NoNewline
    return (Read-Host).Trim('"')
}

function SelectConsoleItem {
    param([string]$Title, [string[]]$Items, [hashtable]$MenuState = @{}, [string]$StateKey = $Title)

    if (-not $Items.Count) { throw 'Menu has no items.' }
    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) {
        throw 'Interactive selection requires a console. Use PowerShell parameters for non-interactive execution.'
    }
    $selected = 0
    # Запоминаем сам пункт, чтобы позиция сохранялась и при изменении порядка списка.
    if ($MenuState.ContainsKey($StateKey)) {
        $previousIndex = [Array]::IndexOf($Items, $MenuState[$StateKey])
        if ($previousIndex -ge 0) { $selected = $previousIndex }
    }
    $previousCursorVisible = [Console]::CursorVisible
    try {
        [Console]::CursorVisible = $false
        while ($true) {
            # Перерисовываем меню целиком, чтобы длинные пути не нарушали положение курсора.
            [Console]::Clear()
            WriteMenuText $Title Title
            WriteMenuText 'Up/Down: select | Enter: confirm | Backspace: back | Esc: cancel' Hint
            Write-Host ''
            for ($index = 0; $index -lt $Items.Count; $index++) {
                if ($index -eq $selected) {
                    WriteMenuText ('> ' + $Items[$index]) Focus
                }
                else { WriteMenuText ('  ' + $Items[$index]) }
            }
            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                'UpArrow' { $selected = ($selected + $Items.Count - 1) % $Items.Count }
                'DownArrow' { $selected = ($selected + 1) % $Items.Count }
                'Enter' {
                    $MenuState[$StateKey] = $Items[$selected]
                    return $selected
                }
                'Backspace' {
                    $MenuState[$StateKey] = $Items[$selected]
                    return -1
                }
                'Escape' { throw 'Operation cancelled. No project changes were written.' }
            }
        }
    }
    finally { [Console]::CursorVisible = $previousCursorVisible }
}

function SelectConsoleComponents {
    param([string]$Title, [string[]]$Items, [hashtable]$InitialModes = @{}, [switch]$Removal, [hashtable]$Catalog = @{})

    if (-not $Items.Count) { throw 'No components available for this operation.' }
    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) {
        throw 'Interactive selection requires a console. Specify Components for non-interactive execution.'
    }
    $marked = @{}
    if (-not $Removal) {
        foreach ($name in $Items) {
            if ($InitialModes.ContainsKey($name)) { $marked[$name] = $InitialModes[$name] }
        }
    }
    $modes = @('Shared', 'Static', 'Dynamic')
    $selected = 0
    $column = 0
    $showDependencies = $false
    $previousCursorVisible = [Console]::CursorVisible
    try {
        [Console]::CursorVisible = $false
        while ($true) {
            # Пересчитываем предварительный набор, сохраняя самостоятельные подключения.
            $roots = if ($Removal) {
                @($InitialModes.Keys | Where-Object { -not $marked.ContainsKey($_) })
            }
            else { @(@($InitialModes.Keys) + @($marked.Keys) | Select-Object -Unique) }
            $requiredBy = @{}
            foreach ($rootName in $roots) {
                if (-not $Catalog.ContainsKey($rootName)) { continue }
                foreach ($dependency in @(GetResolvedComponents @($rootName) $Catalog)) {
                    if ($dependency -eq $rootName) { continue }
                    if (-not $requiredBy.ContainsKey($dependency)) { $requiredBy[$dependency] = @() }
                    $requiredBy[$dependency] += $rootName
                }
            }
            $dependencies = @()
            $activeName = if ($selected -lt $Items.Count) { $Items[$selected] } else { $null }
            if ($showDependencies -and $activeName -and $Catalog.ContainsKey($activeName)) {
                $dependencies = @(GetResolvedComponents @($activeName) $Catalog | Where-Object { $_ -ne $activeName })
            }
            [Console]::Clear()
            WriteMenuText $Title Title
            WriteMenuText 'Up/Down: component | Left/Right: mode | Space: toggle | Enter on Apply: confirm | Backspace: back | Esc: cancel' Hint
            WriteMenuText '/ or .: show/hide dependencies | *: required transitively, not explicitly selected' Hint
            Write-Host ''
            for ($index = 0; $index -le $Items.Count; $index++) {
                $rowRole = if ($index -eq $selected) { 'Focus' } else { 'Text' }
                $prefix = if ($index -eq $selected) { '> ' } else { '  ' }
                WriteMenuText $prefix $rowRole -NoNewline
                if ($index -eq $Items.Count) {
                    WriteMenuText 'Apply' $rowRole
                    continue
                }
                $name = $Items[$index]
                $transitive = $name -notin $roots -and $requiredBy.ContainsKey($name)
                $displayName = $name + $(if ($transitive) { '*' } else { '' })
                $nameRole = if ($name -in $dependencies) { 'Mark' } else { 'Text' }
                if ($Removal) {
                    $check = if ($marked.ContainsKey($name)) { 'x' } else { ' ' }
                    $markRole = if ($check -eq 'x') { 'Mark' } else { 'Text' }
                    WriteMenuText "[$check]" $markRole -NoNewline
                    if ($name -in $dependencies) { $rowRole = 'Mark' }
                    $modeText = if ($InitialModes.ContainsKey($name)) { $InitialModes[$name] } else { 'dependency' }
                    WriteMenuText " $displayName ($modeText)" $rowRole
                    continue
                }
                WriteMenuText $displayName.PadRight(24) $nameRole -NoNewline
                for ($modeIndex = 0; $modeIndex -lt $modes.Count; $modeIndex++) {
                    $focused = $index -eq $selected -and $modeIndex -eq $column
                    $check = if ($marked[$name] -eq $modes[$modeIndex]) { 'x' } else { ' ' }
                    $markRole = if ($check -eq 'x') { 'Mark' } else { 'Text' }
                    $modeRole = if ($focused) { 'Focus' } else { 'Text' }
                    $left = if ($focused) { '<' } else { ' ' }
                    $right = if ($focused) { '>' } else { ' ' }
                    WriteMenuText $left $modeRole -NoNewline
                    WriteMenuText "[$check]" $markRole -NoNewline
                    WriteMenuText (' ' + $modes[$modeIndex] + $right) $modeRole -NoNewline
                    if ($modeIndex -lt $modes.Count - 1) { WriteMenuText '  ' -NoNewline }
                }
                Write-Host ''
            }
            if ($showDependencies -and $activeName) {
                Write-Host ''
                WriteMenuText ("Dependencies: $activeName") Title
                # Два независимых вертикальных списка: строки не обозначают связь между колонками.
                $dependsOnNames = @(if ($dependencies.Count) { $dependencies } else { '(none)' })
                $requiredByNames = @(if ($requiredBy.ContainsKey($activeName)) { $requiredBy[$activeName] | Sort-Object -Unique } else { '(none)' })
                $dependsOnWidth = 'Depends on'.Length
                $requiredByWidth = 'Required by'.Length
                foreach ($name in $dependsOnNames) { $dependsOnWidth = [Math]::Max($dependsOnWidth, $name.Length) }
                foreach ($name in $requiredByNames) { $requiredByWidth = [Math]::Max($requiredByWidth, $name.Length) }
                $separator = '+-' + ('-' * $dependsOnWidth) + '-+-' + ('-' * $requiredByWidth) + '-+'
                WriteMenuText $separator Hint
                WriteMenuText ('| ' + 'Depends on'.PadRight($dependsOnWidth) + ' | ' + 'Required by'.PadRight($requiredByWidth) + ' |') Title
                WriteMenuText $separator Hint
                for ($rowIndex = 0; $rowIndex -lt [Math]::Max($dependsOnNames.Count, $requiredByNames.Count); $rowIndex++) {
                    $leftName = if ($rowIndex -lt $dependsOnNames.Count) { $dependsOnNames[$rowIndex] } else { '' }
                    $rightName = if ($rowIndex -lt $requiredByNames.Count) { $requiredByNames[$rowIndex] } else { '' }
                    WriteMenuText ('| ' + $leftName.PadRight($dependsOnWidth) + ' | ' + $rightName.PadRight($requiredByWidth) + ' |') Mark
                }
                WriteMenuText $separator Hint
            }
            $key = [Console]::ReadKey($true)
            if ($key.KeyChar -eq '/' -or $key.KeyChar -eq '.') {
                $showDependencies = -not $showDependencies
                continue
            }
            switch ($key.Key) {
                'UpArrow' { $selected = ($selected + $Items.Count) % ($Items.Count + 1) }
                'DownArrow' { $selected = ($selected + 1) % ($Items.Count + 1) }
                'LeftArrow' { $column = ($column + $modes.Count - 1) % $modes.Count }
                'RightArrow' { $column = ($column + 1) % $modes.Count }
                'Spacebar' {
                    if ($selected -lt $Items.Count) {
                        $name = $Items[$selected]
                        if ($Removal -and -not $InitialModes.ContainsKey($name)) { continue }
                        $mode = if ($Removal) { $InitialModes[$name] } else { $modes[$column] }
                        if ($marked[$name] -eq $mode) { $marked.Remove($name) }
                        else { $marked[$name] = $mode }
                    }
                }
                'Enter' {
                    if ($selected -eq $Items.Count -and $marked.Count) {
                        return $marked
                    }
                }
                'Escape' { throw 'Operation cancelled. No project changes were written.' }
                'Backspace' { return $null }
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

if (-not $Components -and $ComponentModes.Count) { $Components = @($ComponentModes.Keys) }
$interactive = -not $Components -and -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected
$explicitDisconnect = [bool]$Disconnect
$solutionDirectory = $null
$menuState = @{}
# Навигация завершается до любых изменений файлов; возврат повторяет только этапы выбора.
:Selection while ($true) {
    if ($ProjectOnly) {
        if ($SolutionPath) { throw 'ProjectOnly cannot be combined with SolutionPath.' }
        if (-not $ProjectPath) { $ProjectPath = ReadMenuPath 'Path to consumer .vcxproj' }
    }
    else {
        # Обычный сценарий начинается с решения; consumer выбирается только из его проектов.
        if (-not $SolutionPath) {
            if ([Console]::IsInputRedirected) { throw 'Specify SolutionPath for Shared References, or ProjectOnly for a standalone project.' }
            $SolutionPath = ReadMenuPath 'Path to consumer .sln or solution directory'
        }
        $targetSolution = (Resolve-Path -LiteralPath $SolutionPath).Path
        if (Test-Path -LiteralPath $targetSolution -PathType Container) {
            $solutionDirectory = $targetSolution
            # Ищем решения непосредственно в выбранной папке, без артефактов из подкаталогов.
            $solutions = @(Get-ChildItem -LiteralPath $targetSolution -Filter '*.sln' -File | Sort-Object Name | ForEach-Object FullName)
            if (-not $solutions.Count) { throw "No .sln files found in directory: $targetSolution" }
            $solutionSelection = SelectConsoleItem -Title 'Select consumer solution' -Items $solutions -MenuState $menuState -StateKey "Solution:$solutionDirectory"
            if ($solutionSelection -eq -1) {
                $SolutionPath = $null
                $ProjectPath = $null
                continue Selection
            }
            $targetSolution = $solutions[$solutionSelection]
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
        else {
            $projectSelection = SelectConsoleItem -Title 'Select consumer project' -Items $projects -MenuState $menuState -StateKey "Project:$targetSolution"
            if ($projectSelection -eq -1) {
                $SolutionPath = $solutionDirectory
                continue Selection
            }
            $ProjectPath = $projects[$projectSelection]
        }
    }
    if ($interactive -and -not $Disconnect) {
        $action = SelectConsoleItem -Title $ProjectPath -Items @('Connect / update', 'Disconnect') -MenuState $menuState -StateKey "Action:$ProjectPath"
        if ($action -eq -1) {
            $ProjectPath = $null
            if ($ProjectOnly -or $projects.Count -eq 1) { $SolutionPath = $solutionDirectory }
            continue Selection
        }
        if ($action -eq 1) { $Disconnect = $true }
    }

    # 1. Выбираем явные компоненты; автоматически раскрытые зависимости отдельно не отключаются.
    $connectedComponents = @(GetConnectedComponents $ProjectPath)
    [xml]$currentProject = [IO.File]::ReadAllText($ProjectPath)
    $currentModes = @{}
    foreach ($name in $connectedComponents) {
        $modeNode = $currentProject.SelectSingleNode('/*[local-name()="Project"]/*[local-name()="PropertyGroup" and @Label="UniversalDevKit"]/*[local-name()="UniversalDevKit' + $name + 'Linkage"]')
        $currentModes[$name] = if ($modeNode) { $modeNode.InnerText } else { 'Shared' }
    }
    if ($interactive -and -not $Components) {
        if ($Disconnect -and -not $connectedComponents.Count) {
            WriteMenuText 'No UniversalDevKit components are connected to this project.' Hint
            return
        }
        $menuCatalog = GetComponentCatalog
        $menuItems = if ($Disconnect) { @(GetResolvedComponents $connectedComponents $menuCatalog) } else { @(GetAvailableComponents) }
        $title = if ($Disconnect) { 'Select components to disconnect' } else { 'Select components to connect' }
        $selection = SelectConsoleComponents -Title $title -Items $menuItems -InitialModes $currentModes -Removal:$Disconnect -Catalog $menuCatalog
        if ($null -eq $selection) {
            $Disconnect = $explicitDisconnect
            if ($explicitDisconnect) {
                $ProjectPath = $null
                if ($ProjectOnly -or $projects.Count -eq 1) { $SolutionPath = $solutionDirectory }
            }
            continue Selection
        }
        $Components = @($selection.Keys)
        if (-not $Disconnect) { $ComponentModes = $selection }
        [Console]::Clear()
        WriteMenuText ('Consumer: ' + $ProjectPath) Title
    }
    break Selection
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
    WriteMenuText 'Preparing SolutionInjector...' Title
    # Загрузка и распаковка используют встроенный прогресс PowerShell; временно меняем его палитру.
    $progressForeground = $Host.PrivateData.ProgressForegroundColor
    $progressBackground = $Host.PrivateData.ProgressBackgroundColor
    $progressStyle = $null
    if (Get-Variable PSStyle -ErrorAction SilentlyContinue) { $progressStyle = $PSStyle.Progress.Style }
    try {
        $Host.PrivateData.ProgressForegroundColor = 'DarkGreen'
        $Host.PrivateData.ProgressBackgroundColor = 'Black'
        if ($null -ne $progressStyle) { $PSStyle.Progress.Style = "$([char]27)[38;2;166;185;129m" }
        $solutionInjector = & (Join-Path $PSScriptRoot 'GetSolutionInjector.ps1') -LocalPath $SolutionInjectorPath
    }
    finally {
        $Host.PrivateData.ProgressForegroundColor = $progressForeground
        $Host.PrivateData.ProgressBackgroundColor = $progressBackground
        if ($null -ne $progressStyle) { $PSStyle.Progress.Style = $progressStyle }
    }
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
    foreach ($name in $ComponentModes.Keys) {
        if ($name -cnotin $Components) { throw "Linkage specified for an unselected component: $name" }
    }
    # Режимы проверяем до изменения consumer и решения; старые подключения считаем Shared.
    $resolvedModes = @{}
    foreach ($name in $Components) {
        $mode = if ($ComponentModes.ContainsKey($name)) { $ComponentModes[$name] } elseif ($currentModes.ContainsKey($name)) { $currentModes[$name] } else { 'Shared' }
        if ($mode -cnotin @('Shared', 'Static', 'Dynamic')) { throw "Unsupported linkage for ${name}: $mode" }
        if ($ProjectOnly -and $mode -ne 'Shared') { throw 'Static/Dynamic linkage requires SolutionPath.' }
        if ($mode -ne 'Shared' -and $componentCatalog[$name].Dependencies.Count) {
            throw "Compiled dependencies are not yet configured for ${name}; use Shared for this component."
        }
        foreach ($dependency in @(GetResolvedComponents @($name) $componentCatalog)) {
            if ($resolvedModes.ContainsKey($dependency) -and $resolvedModes[$dependency] -ne $mode) {
                throw "Conflicting linkage for dependency: $dependency"
            }
            $resolvedModes[$dependency] = $mode
        }
    }
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
        WriteMenuText 'Updating solution projects...' Title
        & $solutionInjector $sourceSolution $targetSolution --rootName UniversalDevKit -f MsBuild | ForEach-Object { WriteMenuText $_ Hint }
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
            if ($resolvedModes[$component] -ne 'Shared') { continue }
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
    foreach ($name in $Components) {
        $modeProperty = $document.CreateElement('UniversalDevKit' + $name + 'Linkage', $namespace)
        $modeProperty.InnerText = $resolvedModes[$name]
        [void]$group.AppendChild($document.CreateWhitespace($newline + '    '))
        [void]$group.AppendChild($modeProperty)
    }
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
        # Общие публичные настройки импортируем независимо от способа линковки.
        $publicImport = $document.CreateElement('Import', $namespace)
        $publicImport.SetAttribute('Label', 'UniversalDevKit')
        $publicImport.SetAttribute('Project', (GetRelativePath $projectDirectory (Join-Path $repositoryPath 'Projects/MsBuild/UniversalDevKit.props')))
        [void]$root.InsertBefore($document.CreateWhitespace($newline + '  '), $anchor)
        [void]$root.InsertBefore($publicImport, $anchor)
        $libraryReferences = $document.CreateElement('ItemGroup', $namespace)
        $libraryReferences.SetAttribute('Label', 'UniversalDevKit')
        $compilerSettings = $document.CreateElement('ItemDefinitionGroup', $namespace)
        $compilerSettings.SetAttribute('Label', 'UniversalDevKit')
        $dynamicDefinitions = @()
        $copyTarget = $document.CreateElement('Target', $namespace)
        $copyTarget.SetAttribute('Label', 'UniversalDevKit')
        $copyTarget.SetAttribute('Name', '__UniversalDevKitCopyDynamicLibraries')
        $copyTarget.SetAttribute('AfterTargets', 'Build')
        foreach ($name in $resolvedComponents) {
            $mode = $resolvedModes[$name]
            if ($mode -eq 'Shared') { continue }
            $libraryPath = Join-Path $repositoryPath "Projects/MsBuild/$name/UniversalDevKit.$name.$mode.vcxproj"
            $reference = $document.CreateElement('ProjectReference', $namespace)
            $reference.SetAttribute('Include', (GetRelativePath $projectDirectory $libraryPath))
            [xml]$libraryProject = [IO.File]::ReadAllText($libraryPath)
            $guid = $document.CreateElement('Project', $namespace)
            $guid.InnerText = $libraryProject.Project.PropertyGroup.ProjectGuid | Where-Object { $_ }
            [void]$reference.AppendChild($guid)
            [void]$libraryReferences.AppendChild($reference)
            if ($mode -eq 'Dynamic') {
                $dynamicDefinitions += 'UNIVERSALDEVKIT_' + $name.ToUpperInvariant() + '_DYNAMIC'
                $copy = $document.CreateElement('Copy', $namespace)
                $dllPath = GetRelativePath $projectDirectory (Join-Path $repositoryPath "!artifacts/Windows-`$(Platform)/msbuild/UniversalDevKit.$name.Dynamic/`$(Configuration)/bin/UniversalDevKit.$name.Dynamic.dll")
                $copy.SetAttribute('SourceFiles', $dllPath)
                $copy.SetAttribute('DestinationFolder', '$(OutDir)')
                $copy.SetAttribute('SkipUnchangedFiles', 'true')
                [void]$copyTarget.AppendChild($copy)
            }
        }
        if ($libraryReferences.HasChildNodes) {
            [void]$root.InsertBefore($document.CreateWhitespace($newline + '  '), $anchor)
            [void]$root.InsertBefore($libraryReferences, $anchor)
        }
        if ($dynamicDefinitions.Count) {
            $compile = $document.CreateElement('ClCompile', $namespace)
            $definitions = $document.CreateElement('PreprocessorDefinitions', $namespace)
            $definitions.InnerText = ($dynamicDefinitions -join ';') + ';%(PreprocessorDefinitions)'
            [void]$compile.AppendChild($definitions)
            [void]$compilerSettings.AppendChild($compile)
            [void]$root.InsertBefore($document.CreateWhitespace($newline + '  '), $anchor)
            [void]$root.InsertBefore($compilerSettings, $anchor)
            [void]$root.AppendChild($document.CreateWhitespace($newline + '  '))
            [void]$root.AppendChild($copyTarget)
        }
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
# Форматируем новые блоки интеграции, не меняя содержимое соседних настроек consumer.
function FormatIntegrationNode($Node, [int]$Depth) {
    $children = @($Node.ChildNodes | Where-Object { $_.NodeType -eq [Xml.XmlNodeType]::Element })
    if (-not $children.Count) { return }
    foreach ($child in $children) {
        FormatIntegrationNode $child ($Depth + 1)
        if (-not $child.PreviousSibling -or $child.PreviousSibling.NodeType -ne [Xml.XmlNodeType]::Whitespace) {
            [void]$Node.InsertBefore($document.CreateWhitespace($newline + ('  ' * ($Depth + 1))), $child)
        }
    }
    if ($Node.LastChild.NodeType -ne [Xml.XmlNodeType]::Whitespace) {
        [void]$Node.AppendChild($document.CreateWhitespace($newline + ('  ' * $Depth)))
    }
}
foreach ($node in @($root.SelectNodes('*[@Label="UniversalDevKit"]'))) { FormatIntegrationNode $node 1 }
$updated = $document.OuterXml.TrimEnd([char[]]"`r`n")
if ($updated -cne $original) {
    [IO.File]::WriteAllText($projectFile, $updated, [Text.UTF8Encoding]::new($false))
    WriteMenuText "Updated: $projectFile" Mark
}
else { WriteMenuText 'Project is already up to date.' Hint }

if ($SolutionPath) {
    $referencesToRemove = @($previousSharedProjects + $sharedProjects | Sort-Object Guid -Unique)
    $referencesToAdd = if ($Disconnect) { @() } else { $sharedProjects }
    UpdateSolutionSharedReferences $targetSolution $consumerGuid $referencesToRemove $referencesToAdd

    if ($cleanupRequested -or $ComponentModes.Count) {
        # 1. Ищем корневую папку по типу и имени; повторное отключение без дерева ничего не меняет.
        $content = [IO.File]::ReadAllText($targetSolution)
        $scopePattern = '(?m)^Project\("\{2150E333-8FDC-42A3-9474-1A3956D46DE8\}"\)\s*=\s*"UniversalDevKit",\s*"[^"]+",\s*"\{([^}]+)\}"'
        $scopes = [regex]::Matches($content, $scopePattern)
        if ($scopes.Count -gt 1) { throw 'Ambiguous UniversalDevKit scope; automatic cleanup was not applied.' }
        if ($scopes.Count -eq 1) {
            # 2. Рассчитываем и применяем очистку после записи всех связей consumer.
            # SolutionInjector сохраняет используемые другими проектами зависимости и резервную копию .sln.
            $scopeGuid = '{' + $scopes[0].Groups[1].Value + '}'
            WriteMenuText 'Analyzing dependencies and cleaning unused projects...' Title
            $cleanupOutput = & $solutionInjector prune $targetSolution --scope $scopeGuid --apply --json
            $cleanupExitCode = $LASTEXITCODE
            if ($cleanupExitCode -notin @(0, 2)) {
                throw "Consumer was disconnected, but solution cleanup failed with exit code $cleanupExitCode."
            }
            $cleanupReport = ($cleanupOutput -join "`n") | ConvertFrom-Json
            if ($cleanupReport.schemaVersion -ne 1) { throw 'Unsupported SolutionInjector cleanup report version.' }

            # 3. При неоднозначном анализе оставляем дерево решения и показываем причины.
            if ($cleanupExitCode -eq 2 -or $cleanupReport.blocked) {
                foreach ($issue in $cleanupReport.issues) { WriteMenuText "Cleanup skipped: $issue" Focus }
                WriteMenuText 'Consumer was disconnected; solution projects were retained because dependency analysis was blocked.' Focus
            }
            elseif (-not $cleanupReport.applied) { throw 'SolutionInjector did not apply the cleanup plan.' }
            else {
                WriteMenuText ('Cleanup: removed {0} projects and {1} folders.' -f @($cleanupReport.removedProjects).Count, @($cleanupReport.removedFolders).Count) Mark
            }
        }
    }
}