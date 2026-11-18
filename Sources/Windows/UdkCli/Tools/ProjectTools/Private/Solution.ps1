function Update-ProjectToolsVersionItem([string]$Content, [string]$Path, [switch]$Clean) {
    $guid = Get-ProjectToolsGuid 'ProjectTools.SolutionFolder:!Repository'
    $folderHeader = 'Project("{2150E333-8FDC-42A3-9474-1A3956D46DE8}") = "!Repository", "!Repository", "' + $guid + '"'
    $folderPattern = '(?m)^Project\("\{2150E333-8FDC-42A3-9474-1A3956D46DE8\}"\) = "!Repository", [^\r\n]+\r?\n[\s\S]*?^EndProject(?=\r?$)'
    $itemPattern = '(?m)^[ \t]*[^=\r\n]+ = ' + [regex]::Escape($Path) + '[ \t]*\r?\n'
    if ($Clean) {
        $content = [regex]::Replace($Content, '(?m)^Project\("\{2150E333-8FDC-42A3-9474-1A3956D46DE8\}"\) = [^\r\n]+\r?\n[\s\S]*?^EndProject(?=\r?$)', {
            param($match)
            [regex]::Replace($match.Value, $itemPattern, '')
        })
        return $content
    }
    $folder = [regex]::Match($Content, $folderPattern)
    $item = "`t`t$Path = $Path"
    $section = "`tProjectSection(SolutionItems) = preProject"
    if (-not $folder.Success) {
        $block = @($folderHeader, $section, $item, "`tEndProjectSection", 'EndProject') -join "`n"
        return [regex]::new('(?m)^Global\r?$').Replace($Content, {
            param($match) $block + "`n" + $match.Value
        }, 1)
    }
    if ($folder.Value -match $itemPattern) {
        return $Content
    }
    $sectionPattern = '(?m)^([ \t]*ProjectSection\(SolutionItems\) = preProject)\r?$'
    $updatedFolder = if ($folder.Value -match $sectionPattern) {
        $folder.Value -replace $sectionPattern, "`$1`n$item"
    } else {
        $folder.Value -replace '(?m)^EndProject$', (@($section, $item, "`tEndProjectSection", 'EndProject') -join "`n")
    }
    return $Content.Remove($folder.Index, $folder.Length).Insert($folder.Index, $updatedFolder)
}

function Remove-ProjectToolsEmptyFolders([string]$Content, $FolderGuids) {
    do {
        $previous = $Content
        foreach ($guid in $FolderGuids) {
            $escaped = [regex]::Escape($guid)
            if ($Content -match "(?m)^[ \t]*\{[^}]+\} = $escaped[ \t]*\r?$") {
                continue
            }
            $folder = '(?m)^Project\("\{2150E333-8FDC-42A3-9474-1A3956D46DE8\}"\) = [^\r\n]+, "' + $escaped + '"\r?\n(?:[ \t]*ProjectSection\(SolutionItems\) = preProject\r?\n[ \t]*EndProjectSection\r?\n)?EndProject\r?\n'
            $updated = $Content -replace $folder, ''
            if ($updated -cne $Content) {
                $Content = $updated -replace "(?m)^[ \t]*$escaped = \{[^}]+\}[ \t]*\r?\n", ''
            }
        }
    } while ($Content -cne $previous)
    return $Content
}

function Expand-ProjectToolsSolutionPattern($Model, $Component, [string]$Pattern) {
    if ($Pattern.StartsWith('{projectDirectory}/', [StringComparison]::Ordinal)) {
        if (-not $Component) { throw 'projectDirectory requires a project-level solution filter.' }
        $variant = if ($Component.projectType -eq 'native') { 'Shared' } else { 'DotNet' }
        $projectDirectory = Get-ProjectToolsLayout $Model $Component $variant 'projectDirectory'
        return $projectDirectory + $Pattern.Substring('{projectDirectory}'.Length)
    }
    return $Pattern
}

function Get-ProjectToolsSolutionItems($Model, $Files, [string]$Directory) {
    $items = [ordered]@{}
    $outputs = @{}
    foreach ($file in $Files) {
        $outputs[$file.RelativePath.Replace('\', '/')] = $true
    }
    foreach ($entry in $Model.SolutionFilters) {
        $rule = $entry.Rule
        if (@($rule.PSObject.Properties.Name | Where-Object { $_ -cnotin @('scope', 'filter', 'path', 'generatedPath', 'preserveTree', 'match', 'selection') }).Count -or
            [bool]$rule.path -eq [bool]$rule.generatedPath -or $rule.filter -isnot [string] -or
            $rule.filter -match '[\\:*?"<>|=\r\n]' -or
            @($rule.filter.Split('/') | Where-Object { $_.Trim() -in @('', '.', '..') }).Count) {
            throw 'Expected a solution folder and exactly one Path or Generated selector.'
        }
        $pattern = if ($rule.generatedPath) { $rule.generatedPath } else { $rule.path }
        $pattern = Expand-ProjectToolsSolutionPattern $Model $entry.Component $pattern
        $placementPattern = $pattern
        if ($rule.match) {
            $placementPattern = Expand-ProjectToolsSolutionPattern $Model $entry.Component $rule.match
            $null = Resolve-ProjectToolsPath $Model.Root ($placementPattern.Replace('*', '_').Replace('?', '_'))
        }
        $prefix = ($placementPattern -split '[*?]', 2)[0]
        $base = $prefix.Substring(0, $prefix.LastIndexOf('/') + 1)
        $paths = if ($rule.generatedPath) {
            $null = Resolve-ProjectToolsPath $Model.Root ($pattern.Replace('*', '_').Replace('?', '_'))
            $regex = ConvertTo-ProjectToolsGlobRegex $pattern
            $selectedOutputs = @($outputs.Keys | Where-Object { $_ -cmatch $regex })
            if (-not $selectedOutputs.Count -and $pattern -notmatch '[*?]') {
                throw "Generated file is missing from the plan: $pattern"
            }
            $selectedOutputs
        } else {
            $excludes = switch -CaseSensitive ($rule.selection) {
                'Header' { $entry.Component.excludeHeaders }
                'Source' { $entry.Component.excludeSources }
            }
            Expand-ProjectToolsFiles $Model.Root @($pattern) @($excludes | Where-Object { $_ })
        }
        if ($rule.match) {
            $regex = ConvertTo-ProjectToolsGlobRegex $placementPattern
            $paths = @($paths | Where-Object { $_ -cmatch $regex })
        }
        foreach ($path in ($paths | Sort-Object -CaseSensitive)) {
            $folder = $rule.filter
            if ($rule.preserveTree) {
                $relative = $path.Substring($base.Length)
                if ($relative.Contains('/')) {
                    $folder += '/' + $relative.Substring(0, $relative.LastIndexOf('/'))
                }
            }
            $relativePath = Get-ProjectToolsRelativePath $Directory (Join-Path $Model.Root $path)
            if ($relativePath -match '[=\r\n]') {
                throw "Unsupported solution item path: $relativePath"
            }
            $items[$relativePath] = $folder
        }
    }
    return $items
}

function Update-ProjectToolsSolutionItems([string]$Content, $Items) {
    $owner = '(?m)^\tGlobalSection\(ProjectToolsSolutionItems\) = preSolution\r?\n[\s\S]*?^\tEndGlobalSection\r?\n'
    $folderPattern = '(?m)^Project\("\{2150E333-8FDC-42A3-9474-1A3956D46DE8\}"\) = "([^"]+)", "[^"]+", "(\{[^}]+\})"\r?\n[\s\S]*?^EndProject(?=\r?$)'
    $nestedPattern = '(?m)^\tGlobalSection\(NestedProjects\) = preSolution\r?\n[\s\S]*?^\tEndGlobalSection'
    $itemPattern = '(?m)^\t\t([^=\r\n]+) = ([^\r\n]+)\r?\n'
    $sectionPattern = '(?m)^\tProjectSection\(SolutionItems\) = preProject\r?\n[\s\S]*?^\tEndProjectSection\r?\n'
    # Recover the previous ownership before reconciling individual entries.
    $owned = @{}
    $created = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($line in ([regex]::Match($Content, $owner).Value -split '\r?\n')) {
        if ($line -match '^\t\t(\{[^}]+\}) = folder$') {
            [void]$created.Add($Matches[1])
        } elseif ($line -match '^\t\t(\{[^}]+\}) = (\{[^}]+\}\|.+)$') {
            $owned[$Matches[1]] = $Matches[2]
        }
    }
    $parents = @{}
    $nested = [regex]::Match($Content, $nestedPattern)
    foreach ($match in [regex]::Matches($nested.Value, '(?m)^\t\t(\{[^}]+\}) = (\{[^}]+\})')) {
        $parents[$match.Groups[1].Value] = $match.Groups[2].Value
    }
    $folderIds = @{}
    foreach ($match in [regex]::Matches($Content, $folderPattern)) {
        $guid = $match.Groups[2].Value
        $folderIds[([string]$parents[$guid] + '/' + $match.Groups[1].Value)] = $guid
    }
    # Reuse existing folder identities and create missing branches.
    $wanted = @{}
    $newFolders = [Collections.Generic.List[string]]::new()
    $newParents = [Collections.Generic.List[string]]::new()
    $ownership = [Collections.Generic.List[string]]::new()
    foreach ($path in $Items.Keys) {
        $parent = ''
        $folderPath = ''
        foreach ($segment in $Items[$path].Split('/')) {
            if ($segment -match '["\r\n]') { throw "Invalid solution folder: $segment" }
            $folderPath = ($folderPath + '/' + $segment).TrimStart('/')
            $key = "$parent/$segment"
            $guid = $folderIds[$key]
            if (-not $guid) {
                $guid = Get-ProjectToolsGuid "ProjectTools.SolutionFolder:$folderPath"
                $folderIds[$key] = $guid
                [void]$created.Add($guid)
                $newFolders.Add(('Project("{{2150E333-8FDC-42A3-9474-1A3956D46DE8}}") = "{0}", "{0}", "{1}"' -f $segment, $guid))
                $newFolders.Add('EndProject')
                if ($parent) { $newParents.Add("`t`t$guid = $parent") }
            }
            $parent = $guid
        }
        if (-not $wanted.ContainsKey($parent)) { $wanted[$parent] = [ordered]@{} }
        $wanted[$parent][$path] = $true
        $id = Get-ProjectToolsGuid "ProjectTools.SolutionItem:$parent/$path"
        $ownership.Add("`t`t$id = $parent|$path")
    }
    if ($newFolders.Count) {
        $Content = [regex]::Replace($Content, '(?m)^Global(?=\r?$)', { param($match) ($newFolders -join "`n") + "`n" + $match.Value })
    }
    if ($newParents.Count) {
        $parentLines = $newParents -join "`n"
        if ($nested.Success) {
            $Content = [regex]::Replace($Content, $nestedPattern, { param($match) $match.Value.Insert($match.Value.LastIndexOf("`tEndGlobalSection"), "$parentLines`n") })
        } else {
            $Content = $Content -replace '(?m)^EndGlobal(?=\r?$)', "`tGlobalSection(NestedProjects) = preSolution`n$parentLines`n`tEndGlobalSection`nEndGlobal"
        }
    }
    # Adopt matching entries and remove stale entries owned by ProjectTools.
    $Content = [regex]::Replace($Content, $folderPattern, {
        param($match)
        $guid = $match.Groups[2].Value
        $remaining = $wanted[$guid]
        $section = [regex]::Match($match.Value, $sectionPattern)
        $body = [regex]::Replace($section.Value, $itemPattern, {
            param($item)
            $path = $item.Groups[2].Value
            if ($remaining -and $remaining.Contains($path)) {
                $remaining.Remove($path)
                return $item.Value
            }
            $id = Get-ProjectToolsGuid "ProjectTools.SolutionItem:$guid/$path"
            if ($owned[$id] -ceq "$guid|$path") { return '' }
            return $item.Value
        })
        if ($remaining -and $remaining.Count) {
            $lines = @($remaining.Keys | ForEach-Object { "`t`t$_ = $_" }) -join "`n"
            $body = if ($section.Success) {
                $body.Insert($body.LastIndexOf("`tEndProjectSection"), "$lines`n")
            } else {
                "`tProjectSection(SolutionItems) = preProject`n$lines`n`tEndProjectSection`n"
            }
        }
        if ($body -match '^\s*ProjectSection\(SolutionItems\) = preProject\s+EndProjectSection\s*$') { $body = '' }
        if ($section.Success) { return $match.Value.Remove($section.Index, $section.Length).Insert($section.Index, $body) }
        return $match.Value.Insert($match.Value.Length - 'EndProject'.Length, $body)
    })
    $Content = Remove-ProjectToolsEmptyFolders $Content $created
    $Content = [regex]::Replace($Content, $owner, '')
    foreach ($guid in $created | Sort-Object) {
        if ($Content -match ('(?m)^Project\([^\r\n]+, "' + [regex]::Escape($guid) + '"\r?$')) {
            $ownership.Add("`t`t$guid = folder")
        }
    }
    if ($ownership.Count) {
        $section = (@("`tGlobalSection(ProjectToolsSolutionItems) = preSolution") + @($ownership | Sort-Object) + @("`tEndGlobalSection", 'EndGlobal')) -join "`n"
        $Content = [regex]::Replace($Content, '(?m)^EndGlobal(?=\r?$)', { param($match) $section })
    }
    return $Content
}

function Get-ProjectToolsSolutionUpdate($Model, $Projects, [string]$Executable, [switch]$Clean, $Files) {
    $solution = Resolve-ProjectToolsPath $Model.Root $Model.Settings.solution
    $original = if (Test-Path -LiteralPath $solution) {
        [IO.File]::ReadAllText($solution)
    } else {
        $null
    }
    $directory = Split-Path -Parent $solution
    $token = '.ProjectTools.' + [Guid]::NewGuid().ToString('N')
    $source = Join-Path $directory ($token + '.source.sln')
    $target = Join-Path $directory ($token + '.target.sln')
    $header = @('Microsoft Visual Studio Solution File, Format Version 12.00', '# Visual Studio Version 17')
    $lines = @($header)
    $nested = @()
    $configs = @()
    $shared = @()
    $folderType = '{2150E333-8FDC-42A3-9474-1A3956D46DE8}'
    $projectType = '{8BC9CEB8-8B4A-11D0-8D11-00A0C91BC942}'
    $dotnetProjectType = '{9A19103F-16F7-4668-BE54-9A1E7A4F7556}'
    $folderNames = @{}
    $groupFolders = @{}
    $folderMoves = @{}
    $applicationNames = @($Model.Applications.Values | ForEach-Object name)
    function FindFolderGuid([string]$Name, [string]$Parent, [string]$Identity, [string]$PreviousParent) {
        $previous = $null
        foreach ($match in [regex]::Matches($original, 'Project\("\{2150E333-8FDC-42A3-9474-1A3956D46DE8\}"\) = "' + [regex]::Escape($Name) + '", "[^"]+", "(\{[^}]+\})"')) {
            $candidate = $match.Groups[1].Value
            if (-not $Parent -or $original -match ([regex]::Escape($candidate) + '\s*=\s*' + [regex]::Escape($Parent))) {
                return $candidate
            }
            if ($PreviousParent -and $original -match ([regex]::Escape($candidate) + '\s*=\s*' + [regex]::Escape($PreviousParent))) {
                $previous = $candidate
            }
        }
        if ($previous) {
            return $previous
        }
        return Get-ProjectToolsGuid $Identity
    }
    $explicitLayout = $Model.Manifest.schemaVersion -ge 6
    $templateFolders = [ordered]@{}
    function Add-TemplateFolders([string]$Path) {
        $parent = ''
        $segments = @()
        foreach ($segment in $path.Split('/')) {
            $segments += $segment
            $key = $segments -join '/'
            if (-not $templateFolders.Contains($key)) {
                $guid = FindFolderGuid $segment $parent ('ProjectTools.SolutionFolder:' + $key)
                $templateFolders[$key] = [pscustomobject]@{ Name = $segment; Guid = $guid; Parent = $parent }
            }
            $parent = $templateFolders[$key].Guid
        }
        return $parent
    }
    $writtenFolders = @{}
    if (-not $explicitLayout) {
        $rootName = if ($Model.Settings.solutionFolder) {
            $Model.Settings.solutionFolder
        } else {
            'Projects'
        }
        $rootFolderGuid = FindFolderGuid $rootName '' ('ProjectTools.SolutionFolder:' + $rootName)
        $lines += @(('Project("' + $folderType + '") = "' + $rootName + '", "' + $rootName + '", "' + $rootFolderGuid + '"'), 'EndProject')
        $msbuildGuid = FindFolderGuid 'MsBuild' $rootFolderGuid 'UDK.SolutionFolder:Projects/MsBuild'
        if ($Model.Profile -eq 'udk') {
            $lines += @(('Project("' + $folderType + '") = "MsBuild", "MsBuild", "' + $msbuildGuid + '"'), 'EndProject')
        }
        if ($Model.Profile -eq 'udk') {
            $nested += "`t`t$msbuildGuid = $rootFolderGuid"
        }
        $technologyGuid = if ($Model.Profile -eq 'udk') {
            $msbuildGuid
        } else {
            $rootFolderGuid
        }
    }
    foreach ($project in $Projects) {
        if ($Clean) {
            break
        }
        $name = [IO.Path]::GetFileNameWithoutExtension($project.Path)
        $relative = Get-ProjectToolsRelativePath $directory (Join-Path $Model.Root $project.Path)
        $group = if ($project.Component -in $applicationNames) {
            'Application'
        } else {
            'Library'
        }
        if ($explicitLayout) {
            $parent = Add-TemplateFolders $project.SolutionFolder
            foreach ($folder in $templateFolders.Values) {
                if ($writtenFolders.ContainsKey($folder.Guid)) {
                    continue
                }
                $writtenFolders[$folder.Guid] = $true
                $lines += @(('Project("' + $folderType + '") = "' + $folder.Name + '", "' + $folder.Name + '", "' + $folder.Guid + '"'), 'EndProject')
                if ($folder.Parent) {
                    $nested += "`t`t$($folder.Guid) = $($folder.Parent)"
                }
            }
            $nested += "`t`t$($project.Guid) = $parent"
        } else {
            $groupKey = "$technologyGuid/$group"
            if (-not $groupFolders.ContainsKey($groupKey)) {
                $groupGuid = FindFolderGuid $group $technologyGuid ('ProjectTools.SolutionFolder:' + $groupKey)
                $groupFolders[$groupKey] = $groupGuid
                $lines += @(('Project("' + $folderType + '") = "' + $group + '", "' + $group + '", "' + $groupGuid + '"'), 'EndProject')
                $nested += "`t`t$groupGuid = $technologyGuid"
            }
            $parentGuid = $groupFolders[$groupKey]
            $folderName = $project.Component
            if (-not $folderNames.ContainsKey($folderName)) {
                $folderGuid = FindFolderGuid $folderName $parentGuid ('ProjectTools.SolutionFolder:' + $groupKey + '/' + $folderName) $technologyGuid
                $folderNames[$folderName] = $folderGuid
                $folderMoves[$folderGuid] = @{ From = $technologyGuid; To = $parentGuid }
                $nested += "`t`t$folderGuid = $parentGuid"
                $lines += @(('Project("' + $folderType + '") = "' + $folderName + '", "' + $folderName + '", "' + $folderGuid + '"'), 'EndProject')
            }
            $nested += "`t`t$($project.Guid) = $($folderNames[$folderName])"
        }
        if ($project.Variant -eq 'DotNet') {
            $lines += @(('Project("' + $dotnetProjectType + '") = "' + $name + '", "' + $relative + '", "' + $project.Guid + '"'), 'EndProject')
            foreach ($configuration in $Model.Settings.configurations) { foreach ($platform in $Model.Settings.platforms) {
                $projectPlatform = if ($project.NativePlatform) { $platform } else { 'Any CPU' }
                $configs += "`t`t$($project.Guid).$configuration|$platform.ActiveCfg = $configuration|$projectPlatform"
                $configs += "`t`t$($project.Guid).$configuration|$platform.Build.0 = $configuration|$projectPlatform"
            } }
            continue
        }
        $lines += @(('Project("' + $projectType + '") = "' + $name + '", "' + $relative + '", "' + $project.Guid + '"'), 'EndProject')
        if ($project.Variant -ne 'Shared') {
            foreach ($configuration in $Model.Settings.configurations) { foreach ($platform in $Model.Settings.platforms) {
                $configs += "`t`t$($project.Guid).$configuration|$platform.ActiveCfg = $configuration|$platform"
                $configs += "`t`t$($project.Guid).$configuration|$platform.Build.0 = $configuration|$platform"
            } }
            $sharedProject = @($Projects | Where-Object {
                $_.Component -eq $project.Component -and $_.Variant -eq 'Shared'
            })[0]
            $sharedPath = Get-ProjectToolsRelativePath $directory (Join-Path $Model.Root $sharedProject.Path)
            $shared += "`t`t$sharedPath*$($project.Guid.ToLowerInvariant())*SharedItemsImports = 4"
        } else {
            $shared += "`t`t$relative*$($project.Guid.ToLowerInvariant())*SharedItemsImports = 9"
        }
    }
    $lines += @('Global', "`tGlobalSection(SolutionConfigurationPlatforms) = preSolution")
    foreach ($configuration in $Model.Settings.configurations) {
        foreach ($platform in $Model.Settings.platforms) {
            $lines += "`t`t$configuration|$platform = $configuration|$platform"
        }
    }
    $lines += @("`tEndGlobalSection", "`tGlobalSection(ProjectConfigurationPlatforms) = postSolution") + $configs + @("`tEndGlobalSection", "`tGlobalSection(NestedProjects) = preSolution") + $nested + @("`tEndGlobalSection", "`tGlobalSection(SharedMSBuildProjectFiles) = preSolution") + $shared + @("`tEndGlobalSection", 'EndGlobal')
    $sourceContent = if ($Clean) {
        (@($header) + @('Global', 'EndGlobal')) -join "`n"
    } else {
        $lines -join "`n"
    }
    $empty = (@($header) + @('Global', "`tGlobalSection(SolutionConfigurationPlatforms) = preSolution") + @($Model.Settings.configurations | ForEach-Object {
        $configuration = $_; $Model.Settings.platforms | ForEach-Object {
            "`t`t$configuration|$_ = $configuration|$_"
        }
    }) + @("`tEndGlobalSection", 'EndGlobal')) -join "`n"
    try {
        [IO.File]::WriteAllText($source, $sourceContent, [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText($target, $(if ($null -ne $original) {
            $original
        } else {
            $empty
        }), [Text.UTF8Encoding]::new($false))
        $arguments = @('sync', $source, $target, '--owner', 'ProjectTools', '--apply', '--json')
        # The component contract explicitly selects these project identities for migration.
        if (-not $Clean) {
            foreach ($project in $Projects) {
                $arguments += @('--adopt', $project.Guid)
            }
        }
        $result = & $Executable @arguments
        if ($LASTEXITCODE -ne 0) {
            throw "SolutionInjector sync failed: $result"
        }
        $report = $result | ConvertFrom-Json
        if ($report.schemaVersion -ne 1 -or -not $report.applied -or $report.blocked) {
            throw 'Unsupported or blocked SolutionInjector sync report.'
        }
        $content = [IO.File]::ReadAllText($target).TrimEnd([char[]]"`r`n")
        $syncContent = $content
        # SolutionInjector preserves the parents of existing solution folders.
        foreach ($folderGuid in $folderMoves.Keys) {
            $move = $folderMoves[$folderGuid]
            $pattern = '(?m)^([ \t]*' + [regex]::Escape($folderGuid) + '[ \t]*=[ \t]*)' + [regex]::Escape($move.From) + '(?=[ \t]*\r?$)'
            $content = [regex]::Replace($content, $pattern, ('${1}' + $move.To))
        }
        $versionPath = Join-Path $Model.Root '.udk-version'
        $relativeVersion = Get-ProjectToolsRelativePath $directory $versionPath
        if ($Clean) {
            $content = Update-ProjectToolsVersionItem $content $relativeVersion -Clean
            if ($explicitLayout) {
                foreach ($project in $Projects) {
                    $null = Add-TemplateFolders $project.SolutionFolder
                }
                $folderGuids = @($templateFolders.Keys | ForEach-Object {
                    Get-ProjectToolsGuid ('ProjectTools.SolutionFolder:' + $_)
                })
                $folderGuids += Get-ProjectToolsGuid 'ProjectTools.SolutionFolder:!Repository'
                $content = Remove-ProjectToolsEmptyFolders $content $folderGuids
            } else {
                $rootGuid = Get-ProjectToolsGuid ('ProjectTools.SolutionFolder:' + $rootName)
                $technologyGuid = if ($Model.Profile -eq 'udk') {
                    Get-ProjectToolsGuid 'UDK.SolutionFolder:Projects/MsBuild'
                } else {
                    $rootGuid
                }
                $folderGuids = @($rootGuid, $technologyGuid, (Get-ProjectToolsGuid 'ProjectTools.SolutionFolder:!Repository'))
                foreach ($group in @('Application', 'Library')) {
                    $groupKey = "$technologyGuid/$group"
                    $folderGuids += Get-ProjectToolsGuid ('ProjectTools.SolutionFolder:' + $groupKey)
                    foreach ($folder in [regex]::Matches($content, '(?m)^Project\("\{2150E333-8FDC-42A3-9474-1A3956D46DE8\}"\) = "([^"]+)"')) {
                        $folderGuids += Get-ProjectToolsGuid ('ProjectTools.SolutionFolder:' + $groupKey + '/' + $folder.Groups[1].Value)
                    }
                }
                $content = Remove-ProjectToolsEmptyFolders $content $folderGuids
            }
        } elseif (Test-Path -LiteralPath $versionPath -PathType Leaf) {
            $content = Update-ProjectToolsVersionItem $content $relativeVersion
        }
        if ($Model.SolutionFilters.Count -or $content.Contains('GlobalSection(ProjectToolsSolutionItems)')) {
            $items = if ($Clean) { [ordered]@{} } else { Get-ProjectToolsSolutionItems $Model $Files $directory }
            $content = Update-ProjectToolsSolutionItems $content $items
        }
        if ($null -ne $original -and -not $report.changed -and $content -ceq $syncContent) {
            return
        }
        if ($content -cne $original) {
            return [pscustomobject]@{ Path = $solution; RelativePath = $Model.Settings.solution; Content = $content; Original = $original }
        }
    } finally {
        foreach ($file in Get-ChildItem -LiteralPath $directory -File | Where-Object Name -like ($token + '*')) {
            Remove-Item -LiteralPath $file.FullName
        }
    }
}