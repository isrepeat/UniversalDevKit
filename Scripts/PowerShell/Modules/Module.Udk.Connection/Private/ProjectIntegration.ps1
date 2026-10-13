function Invoke-UdkConnectionPlan {
    param(
        $Plan,
        [switch]$Preview,
        [scriptblock]$WriteStatus = { param($Text, $Role) Write-Information $Text -InformationAction Continue },
        [scriptblock]$ResolveTool = { param($RepositoryPath, $LocalPath) & (Join-Path $RepositoryPath 'Scripts/PowerShell/GetSolutionInjector.ps1') -LocalPath $LocalPath }
    )

    $ErrorActionPreference = 'Stop'
    $Request = $Plan.Request
    $ProjectPath = $Request.ProjectPath
    $SolutionPath = $Request.SolutionPath
    $Components = @($Request.Components)
    $ComponentModes = $Request.ComponentModes
    $ProjectOnly = [bool]$Request.ProjectOnly
    $Disconnect = [bool]$Request.Disconnect
    $SolutionInjectorPath = $Request.SolutionInjectorPath
    $repositoryPath = $Plan.RepositoryPath
    $integrationPath = Join-Path $repositoryPath 'Projects/MsBuild/UniversalDevKit.Sources.targets'
    $sharedReferencesCondition = '''$(__IsUniversalDevKitSharedReferences)'' == ''true'''
    $targetSolution = $SolutionPath
    $Components = $Plan.Components
    $resolvedComponents = $Plan.ResolvedComponents
    $resolvedModes = $Plan.ResolvedModes
    $Disconnect = $Plan.Disconnect
    $cleanupRequested = $Plan.CleanupRequested

    if ($SolutionPath -and -not $Preview) {
        & $WriteStatus 'Preparing SolutionInjector...' Title
        $solutionInjector = & $ResolveTool $repositoryPath $SolutionInjectorPath
    }
    $projectFile = (Resolve-Path -LiteralPath $ProjectPath).Path
    if ([IO.Path]::GetExtension($projectFile) -ne '.vcxproj') {
        throw 'Expected .vcxproj file.'
    }
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
    $newline = if ($original.Contains("`r`n")) {
        "`r`n"
    } else {
        "`n"
    }
    $root = $document.DocumentElement
    $sharedProjects = @()
    $previousSharedProjects = @()
    if ($SolutionPath) {
        $sourceSolution = Join-Path $repositoryPath 'UniversalDevKit.sln'
        if (-not $Disconnect -and -not $Preview) {
            # Повторная вставка восстанавливает удалённые очисткой компоненты без дублирования оставшихся.
            & $WriteStatus 'Updating solution projects...' Title
            & $solutionInjector $sourceSolution $targetSolution --rootName UniversalDevKit -f MsBuild | ForEach-Object { & $WriteStatus $_ Hint }
            if ($LASTEXITCODE -ne 0) {
                throw "SolutionInjector failed with exit code $LASTEXITCODE."
            }
        }
        if (-not $Disconnect -and -not $Preview) {
            RemoveSolutionBuildItems $targetSolution
        }
        $solutionSharedProjects = GetSolutionSharedProjects $targetSolution
        $previousSharedPaths = @($root.SelectNodes('*[local-name()="ImportGroup" and @Label="Shared" and @Condition="' + $sharedReferencesCondition + '"]/*[local-name()="Import"]') |
            ForEach-Object {
                [IO.Path]::GetFullPath((Join-Path $projectDirectory $_.GetAttribute('Project')))
            })
        $previousSharedProjects = @($solutionSharedProjects.Values | Where-Object { $_.Path -in $previousSharedPaths })
        if (-not $Disconnect) {
            foreach ($component in $resolvedComponents) {
                if ($resolvedModes[$component] -ne 'Shared') {
                    continue
                }
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
        if ($existing.Count -and $SolutionPath) {
            throw 'Unmanaged UniversalDevKit Sources.targets import found; remove it before using Shared References.'
        }
        if ($existing.Count -and -not $SolutionPath) {
            throw 'Unmanaged UniversalDevKit import found; remove it before using Connect.'
        }
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
        if (-not $anchor) {
            throw 'Microsoft.Cpp.targets import not found.'
        }
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
            $runtimeItems = $document.CreateElement('ItemGroup', $namespace)
            $runtimeItems.SetAttribute('Label', 'UniversalDevKit')
            foreach ($name in $resolvedComponents) {
                $mode = $resolvedModes[$name]
                if ($mode -eq 'Shared') {
                    continue
                }
                $libraryPath = Join-Path $repositoryPath "Projects/MsBuild/$name/UniversalDevKit.$name.$mode.vcxproj"
                $reference = $document.CreateElement('ProjectReference', $namespace)
                $reference.SetAttribute('Include', (GetRelativePath $projectDirectory $libraryPath))
                [xml]$libraryProject = [IO.File]::ReadAllText($libraryPath)
                $guid = $document.CreateElement('Project', $namespace)
                $guid.InnerText = $libraryProject.Project.PropertyGroup.ProjectGuid | Where-Object { $_ }
                [void]$reference.AppendChild($guid)
                $link = $document.CreateElement('LinkLibraryDependencies', $namespace)
                $link.InnerText = if ($name -cin $Plan.LinkComponents) {
                    'true'
                } else {
                    'false'
                }
                [void]$reference.AppendChild($link)
                [void]$libraryReferences.AppendChild($reference)
                if ($name -cin $Plan.DefinitionComponents) {
                    $dynamicDefinitions += 'UNIVERSALDEVKIT_' + $name.ToUpperInvariant() + '_DYNAMIC'
                }
                if ($name -cin $Plan.RuntimeComponents) {
                    $runtime = $document.CreateElement('__UniversalDevKitRuntimeProject', $namespace)
                    $runtime.SetAttribute('Include', (GetRelativePath $projectDirectory $libraryPath))
                    [void]$runtimeItems.AppendChild($runtime)
                }
            }
            if ($libraryReferences.HasChildNodes) {
                [void]$root.InsertBefore($document.CreateWhitespace($newline + '  '), $anchor)
                [void]$root.InsertBefore($libraryReferences, $anchor)
            }
            if ($Plan.RequirementComponents.Count) {
                $compile = $document.CreateElement('ClCompile', $namespace)
                $includeDirectories = $document.CreateElement('AdditionalIncludeDirectories', $namespace)
                $includeDirectories.InnerText = (@($Plan.RequirementComponents | ForEach-Object {
                    GetRelativePath $projectDirectory (Join-Path $repositoryPath "Includes/$_")
                }) -join ';') + ';%(AdditionalIncludeDirectories)'
                [void]$compile.AppendChild($includeDirectories)
                $definitions = $document.CreateElement('PreprocessorDefinitions', $namespace)
                $definitions.InnerText = ($dynamicDefinitions -join ';') + ';%(PreprocessorDefinitions)'
                [void]$compile.AppendChild($definitions)
                [void]$compilerSettings.AppendChild($compile)
                [void]$root.InsertBefore($document.CreateWhitespace($newline + '  '), $anchor)
                [void]$root.InsertBefore($compilerSettings, $anchor)
            }
            # Публичные требования языка и системные библиотеки финальной статической линковки.
            $requirementRegistry = Get-UdkComponentRegistry $repositoryPath
            $requirementGroup = $document.CreateElement('ItemGroup', $namespace)
            $requirementGroup.SetAttribute('Label', 'UniversalDevKit')
            foreach ($name in $resolvedComponents) {
                $compile = $name -cin $Plan.RequirementComponents
                $system = $name -cin $Plan.SystemLibraryComponents
                [xml]$requirementXml = '<Project xmlns="' + $namespace + '">' + (Get-UdkRequirementItemsXml $name $requirementRegistry[$name].Requirements $compile $system) + '</Project>'
                foreach ($item in @($requirementXml.DocumentElement.FirstChild.ChildNodes)) {
                    [void]$requirementGroup.AppendChild($document.ImportNode($item, $true))
                }
            }
            [void]$root.InsertBefore($document.CreateWhitespace($newline + '  '), $anchor)
            [void]$root.InsertBefore($requirementGroup, $anchor)
            $requirementsImport = $document.CreateElement('Import', $namespace)
            $requirementsImport.SetAttribute('Label', 'UniversalDevKit')
            $requirementsImport.SetAttribute('Condition', '''$(__IsUniversalDevKitRequirementsImported)'' != ''true''')
            $requirementsImport.SetAttribute('Project', (GetRelativePath $projectDirectory (Join-Path $repositoryPath 'Projects/MsBuild/UniversalDevKit.Requirements.targets')))
            [void]$root.InsertBefore($document.CreateWhitespace($newline + '  '), $anchor)
            [void]$root.InsertBefore($requirementsImport, $anchor)
            # Отпечатки реестра компонентов останавливают сборку устаревшего подключения до компиляции.
            $manifest = Get-Content -LiteralPath (Join-Path $repositoryPath 'Components.json') -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($componentRegistryPath in @('Components.json') + @($manifest.includes)) {
                $componentRegistryFile = Join-Path $repositoryPath $componentRegistryPath
                $componentRegistryItem = $document.CreateElement('__UniversalDevKitComponentRegistryFile', $namespace)
                $componentRegistryItem.SetAttribute('Include', (GetRelativePath $projectDirectory $componentRegistryFile))
                $expectedHash = $document.CreateElement('ExpectedHash', $namespace)
                $expectedHash.InnerText = (Get-FileHash -LiteralPath $componentRegistryFile -Algorithm SHA256).Hash
                [void]$componentRegistryItem.AppendChild($expectedHash)
                [void]$runtimeItems.AppendChild($componentRegistryItem)
            }
            if ($runtimeItems.HasChildNodes) {
                [void]$root.InsertBefore($document.CreateWhitespace($newline + '  '), $anchor)
                [void]$root.InsertBefore($runtimeItems, $anchor)
                $runtimeImport = $document.CreateElement('Import', $namespace)
                $runtimeImport.SetAttribute('Label', 'UniversalDevKit')
                $runtimeImport.SetAttribute('Project', (GetRelativePath $projectDirectory (Join-Path $repositoryPath 'Projects/MsBuild/UniversalDevKit.Runtime.targets')))
                [void]$root.AppendChild($document.CreateWhitespace($newline + '  '))
                [void]$root.AppendChild($runtimeImport)
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
        if (-not $children.Count) {
            return
        }
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
    # Форматируем атрибуты только собственных блоков Connect, сохраняя остальной проект.
    $integrationNodes = @($root.SelectNodes('*[@Label="UniversalDevKit"]'))
    $integrationNodes += @($root.SelectNodes('*[local-name()="ImportGroup" and @Label="Shared" and @Condition="' + $sharedReferencesCondition + '"]'))
    foreach ($node in $integrationNodes) {
        $originalNode = $node.OuterXml.Replace(' xmlns="' + $namespace + '"', '')
        $formattedNode = (Format-UdkXmlAttributes ('  ' + $originalNode)).Substring(2)
        $updated = $updated.Replace($originalNode, $formattedNode)
    }
    if ($Preview) {
        return $updated
    }
    if ($updated -cne $original) {
        [IO.File]::WriteAllText($projectFile, $updated, [Text.UTF8Encoding]::new($false))
        & $WriteStatus "Updated: $projectFile" Mark
    }
    else {
        & $WriteStatus 'Project is already up to date.' Hint
    }

    if ($SolutionPath) {
        $referencesToRemove = @($previousSharedProjects + $sharedProjects | Sort-Object Guid -Unique)
        $referencesToAdd = if ($Disconnect) {
            @()
        } else {
            $sharedProjects
        }
        UpdateSolutionSharedReferences $targetSolution $consumerGuid $referencesToRemove $referencesToAdd -WriteStatus $WriteStatus

        if ($cleanupRequested -or $ComponentModes.Count) {
            # 1. Ищем корневую папку по типу и имени; повторное отключение без дерева ничего не меняет.
            $content = [IO.File]::ReadAllText($targetSolution)
            $scopePattern = '(?m)^Project\("\{2150E333-8FDC-42A3-9474-1A3956D46DE8\}"\)\s*=\s*"UniversalDevKit",\s*"[^"]+",\s*"\{([^}]+)\}"'
            $scopes = [regex]::Matches($content, $scopePattern)
            if ($scopes.Count -gt 1) {
                throw 'Ambiguous UniversalDevKit scope; automatic cleanup was not applied.'
            }
            if ($scopes.Count -eq 1) {
                # 2. Рассчитываем и применяем очистку после записи всех связей consumer.
                # SolutionInjector сохраняет используемые другими проектами зависимости и резервную копию .sln.
                $scopeGuid = '{' + $scopes[0].Groups[1].Value + '}'
                & $WriteStatus 'Analyzing dependencies and cleaning unused projects...' Title
                $cleanupOutput = & $solutionInjector prune $targetSolution --scope $scopeGuid --apply --json
                $cleanupExitCode = $LASTEXITCODE
                if ($cleanupExitCode -notin @(0, 2)) {
                    throw "Consumer was disconnected, but solution cleanup failed with exit code $cleanupExitCode."
                }
                $cleanupReport = ($cleanupOutput -join "`n") | ConvertFrom-Json
                if ($cleanupReport.schemaVersion -ne 1) {
                    throw 'Unsupported SolutionInjector cleanup report version.'
                }

                # 3. При неоднозначном анализе оставляем дерево решения и показываем причины.
                if ($cleanupExitCode -eq 2 -or $cleanupReport.blocked) {
                    foreach ($issue in $cleanupReport.issues) { & $WriteStatus "Cleanup skipped: $issue" Focus }
                    & $WriteStatus 'Consumer was disconnected; solution projects were retained because dependency analysis was blocked.' Focus
                }
                elseif (-not $cleanupReport.applied) {
                    throw 'SolutionInjector did not apply the cleanup plan.'
                }
                else {
                    & $WriteStatus ('Cleanup: removed {0} projects and {1} folders.' -f @($cleanupReport.removedProjects).Count, @($cleanupReport.removedFolders).Count) Mark
                }
            }
        }
    }
}