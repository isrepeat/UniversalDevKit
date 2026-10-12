function Show-UdkConnectionWizard {
    param(
        [string]$ProjectPath,
        [string[]]$Components,
        [hashtable]$ComponentModes = @{},
        [string]$SolutionPath,
        [string]$SolutionInjectorPath,
        [switch]$ProjectOnly,
        [switch]$Disconnect,
        [string]$RepositoryPath,
        [hashtable]$ComponentRegistry
    )

    if (-not $Components -and $ComponentModes.Count) {
        $Components = @($ComponentModes.Keys)
    }
    $interactive = -not $Components -and -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected
    $explicitDisconnect = [bool]$Disconnect
    $solutionDirectory = $null
    $menuState = @{}
    # Навигация завершается до любых изменений файлов; возврат повторяет только этапы выбора.
    :Selection while ($true) {
        if ($ProjectOnly) {
            if ($SolutionPath) {
                throw 'ProjectOnly cannot be combined with SolutionPath.'
            }
            if (-not $ProjectPath) {
                $ProjectPath = ReadMenuPath 'Path to consumer .vcxproj'
            }
        }
        else {
            # Обычный сценарий начинается с решения; consumer выбирается только из его проектов.
            if (-not $SolutionPath) {
                if ([Console]::IsInputRedirected) {
                    throw 'Specify SolutionPath for Shared References, or ProjectOnly for a standalone project.'
                }
                $SolutionPath = ReadMenuPath 'Path to consumer .sln or solution directory'
            }
            $targetSolution = (Resolve-Path -LiteralPath $SolutionPath).Path
            if (Test-Path -LiteralPath $targetSolution -PathType Container) {
                $solutionDirectory = $targetSolution
                # Ищем решения непосредственно в выбранной папке, без артефактов из подкаталогов.
                $solutions = @(Get-ChildItem -LiteralPath $targetSolution -Filter '*.sln' -File | Sort-Object Name | ForEach-Object FullName)
                if (-not $solutions.Count) {
                    throw "No .sln files found in directory: $targetSolution"
                }
                $solutionSelection = SelectConsoleItem -Title 'Select consumer solution' -Items $solutions -MenuState $menuState -StateKey "Solution:$solutionDirectory"
                if ($solutionSelection -eq -1) {
                    $SolutionPath = $null
                    $ProjectPath = $null
                    continue Selection
                }
                $targetSolution = $solutions[$solutionSelection]
            }
            $SolutionPath = $targetSolution
            if ([IO.Path]::GetExtension($targetSolution) -ne '.sln') {
                throw 'Expected target .sln file.'
            }
            $projects = @(@(foreach ($line in Get-Content -LiteralPath $targetSolution) {
                if ($line -match '^Project\(.*\)\s*=\s*"[^"]*",\s*"([^"]+\.vcxproj)"') {
                    $candidate = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $targetSolution) $Matches[1]))
                    # Проекты самой библиотеки не являются потребителями.
                    if (-not $candidate.StartsWith($repositoryPath + '\', [StringComparison]::OrdinalIgnoreCase)) {
                        $candidate
                    }
                }
            }) | Sort-Object -Unique)
            if (-not $projects.Count) {
                throw 'No consumer C++ projects found in solution.'
            }
            if ($ProjectPath) {
                $ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
                if ($ProjectPath -notin $projects) {
                    throw 'Selected consumer project is not part of the target solution.'
                }
            }
            elseif ($projects.Count -eq 1) {
                $ProjectPath = $projects[0]
            }
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
            $unavailableItems = @{}
            $actionState = Module.Udk.Connection\Get-UdkConnectionState -ProjectPath $ProjectPath
            if (-not $actionState.Components.Count) {
                $unavailableItems['Disconnect'] = 'No UniversalDevKit components are connected to this project.'
            }
            $action = SelectConsoleItem -Title $ProjectPath -Items @('Connect / update', 'Disconnect') -MenuState $menuState -StateKey "Action:$ProjectPath" -UnavailableItems $unavailableItems
            if ($action -eq -1) {
                $ProjectPath = $null
                if ($ProjectOnly -or $projects.Count -eq 1) {
                    $SolutionPath = $solutionDirectory
                }
                continue Selection
            }
            if ($action -eq 1) {
                $Disconnect = $true
            }
        }

        # 1. Выбираем явные компоненты; автоматически раскрытые зависимости отдельно не отключаются.
        $connectedComponents = @((Module.Udk.Connection\Get-UdkConnectionState -ProjectPath $ProjectPath).Components)
        [xml]$currentProject = [IO.File]::ReadAllText($ProjectPath)
        $currentModes = @{}
        foreach ($name in $connectedComponents) {
            $modeNode = $currentProject.SelectSingleNode('/*[local-name()="Project"]/*[local-name()="PropertyGroup" and @Label="UniversalDevKit"]/*[local-name()="UniversalDevKit' + $name + 'Linkage"]')
            $currentModes[$name] = if ($modeNode) {
                $modeNode.InnerText
            } else {
                'Shared'
            }
        }
        if ($interactive -and -not $Components) {
            if ($Disconnect -and -not $connectedComponents.Count) {
                # Даже при явном -Disconnect остаёмся в меню; выход возможен через Backspace или Esc.
                $action = SelectConsoleItem -Title $ProjectPath -Items @('Disconnect') -MenuState $menuState -StateKey "Action:$ProjectPath" -UnavailableItems @{ Disconnect = 'No UniversalDevKit components are connected to this project.' }
                if ($action -eq -1) {
                    $ProjectPath = $null
                    if ($ProjectOnly -or $projects.Count -eq 1) {
                        $SolutionPath = $solutionDirectory
                    }
                    continue Selection
                }
            }
            $menuComponentRegistry = $ComponentRegistry
            $menuItems = if ($Disconnect) {
                @(Module.Udk.Connection\Resolve-UdkComponents $connectedComponents $menuComponentRegistry)
            } else {
                @($ComponentRegistry.Keys | Sort-Object)
            }
            $title = if ($Disconnect) {
                'Select components to disconnect'
            } else {
                'Select components to connect'
            }
            $selection = SelectConsoleComponents -Title $title -Items $menuItems -InitialModes $currentModes -Removal:$Disconnect -ComponentRegistry $menuComponentRegistry -ProjectOnly:$ProjectOnly
            if ($null -eq $selection) {
                $Disconnect = $explicitDisconnect
                if ($explicitDisconnect) {
                    $ProjectPath = $null
                    if ($ProjectOnly -or $projects.Count -eq 1) {
                        $SolutionPath = $solutionDirectory
                    }
                }
                continue Selection
            }
            $Components = @($selection.Keys)
            if (-not $Disconnect) {
                $ComponentModes = $selection
            }
            [Console]::Clear()
            Write-UdkConsoleText ('Consumer: ' + $ProjectPath) Title
        }
        break Selection
    }

    return [pscustomobject]@{
        ProjectPath = $ProjectPath
        SolutionPath = $SolutionPath
        Components = @($Components)
        ComponentModes = $ComponentModes
        ProjectOnly = [bool]$ProjectOnly
        Disconnect = [bool]$Disconnect
        SolutionInjectorPath = $SolutionInjectorPath
    }
}