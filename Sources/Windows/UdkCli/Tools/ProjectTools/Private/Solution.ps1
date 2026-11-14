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
        return [regex]::new('(?m)^Global\r?$').Replace($Content, { param($match) $block + "`n" + $match.Value }, 1)
    }
    if ($folder.Value -match $itemPattern) { return $Content }
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
            if ($Content -match "(?m)^[ \t]*\{[^}]+\} = $escaped[ \t]*\r?$") { continue }
            $folder = '(?m)^Project\("\{2150E333-8FDC-42A3-9474-1A3956D46DE8\}"\) = [^\r\n]+, "' + $escaped + '"\r?\n(?:[ \t]*ProjectSection\(SolutionItems\) = preProject\r?\n[ \t]*EndProjectSection\r?\n)?EndProject\r?\n'
            $updated = $Content -replace $folder, ''
            if ($updated -cne $Content) { $Content = $updated -replace "(?m)^[ \t]*$escaped = \{[^}]+\}[ \t]*\r?\n", '' }
        }
    } while ($Content -cne $previous)
    return $Content
}

function Get-ProjectToolsSolutionUpdate($Model, $Projects, [string]$Executable, [switch]$Clean) {
    $solution = Resolve-ProjectToolsPath $Model.Root $Model.Settings.solution
    $original = if (Test-Path -LiteralPath $solution) { [IO.File]::ReadAllText($solution) } else { $null }
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
            if (-not $Parent -or $original -match ([regex]::Escape($candidate) + '\s*=\s*' + [regex]::Escape($Parent))) { return $candidate }
            if ($PreviousParent -and $original -match ([regex]::Escape($candidate) + '\s*=\s*' + [regex]::Escape($PreviousParent))) { $previous = $candidate }
        }
        if ($previous) { return $previous }
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
        $rootName = if ($Model.Settings.solutionFolder) { $Model.Settings.solutionFolder } else { 'Projects' }
        $rootFolderGuid = FindFolderGuid $rootName '' ('ProjectTools.SolutionFolder:' + $rootName)
        $lines += @(('Project("' + $folderType + '") = "' + $rootName + '", "' + $rootName + '", "' + $rootFolderGuid + '"'), 'EndProject')
        $msbuildGuid = FindFolderGuid 'MsBuild' $rootFolderGuid 'UDK.SolutionFolder:Projects/MsBuild'
        if ($Model.Profile -eq 'udk') { $lines += @(('Project("' + $folderType + '") = "MsBuild", "MsBuild", "' + $msbuildGuid + '"'), 'EndProject') }
        if ($Model.Profile -eq 'udk') { $nested += "`t`t$msbuildGuid = $rootFolderGuid" }
        $technologyGuid = if ($Model.Profile -eq 'udk') { $msbuildGuid } else { $rootFolderGuid }
    }
    foreach ($project in $Projects) {
        if ($Clean) { break }
        $name = [IO.Path]::GetFileNameWithoutExtension($project.Path)
        $relative = Get-ProjectToolsRelativePath $directory (Join-Path $Model.Root $project.Path)
        $group = if ($project.Component -in $applicationNames) { 'Application' } else { 'Library' }
        if ($explicitLayout) {
            $parent = Add-TemplateFolders $project.SolutionFolder
            foreach ($folder in $templateFolders.Values) {
                if ($writtenFolders.ContainsKey($folder.Guid)) { continue }
                $writtenFolders[$folder.Guid] = $true
                $lines += @(('Project("' + $folderType + '") = "' + $folder.Name + '", "' + $folder.Name + '", "' + $folder.Guid + '"'), 'EndProject')
                if ($folder.Parent) { $nested += "`t`t$($folder.Guid) = $($folder.Parent)" }
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
                $configs += "`t`t$($project.Guid).$configuration|$platform.ActiveCfg = $configuration|Any CPU"
                $configs += "`t`t$($project.Guid).$configuration|$platform.Build.0 = $configuration|Any CPU"
            } }
            continue
        }
        $lines += @(('Project("' + $projectType + '") = "' + $name + '", "' + $relative + '", "' + $project.Guid + '"'), 'EndProject')
        if ($project.Variant -ne 'Shared') {
            foreach ($configuration in $Model.Settings.configurations) { foreach ($platform in $Model.Settings.platforms) {
                $configs += "`t`t$($project.Guid).$configuration|$platform.ActiveCfg = $configuration|$platform"
                $configs += "`t`t$($project.Guid).$configuration|$platform.Build.0 = $configuration|$platform"
            } }
            $sharedProject = @($Projects | Where-Object { $_.Component -eq $project.Component -and $_.Variant -eq 'Shared' })[0]
            $sharedPath = Get-ProjectToolsRelativePath $directory (Join-Path $Model.Root $sharedProject.Path)
            $shared += "`t`t$sharedPath*$($project.Guid.ToLowerInvariant())*SharedItemsImports = 4"
        } else {
            $shared += "`t`t$relative*$($project.Guid.ToLowerInvariant())*SharedItemsImports = 9"
        }
    }
    $lines += @('Global', "`tGlobalSection(SolutionConfigurationPlatforms) = preSolution")
    foreach ($configuration in $Model.Settings.configurations) { foreach ($platform in $Model.Settings.platforms) { $lines += "`t`t$configuration|$platform = $configuration|$platform" } }
    $lines += @("`tEndGlobalSection", "`tGlobalSection(ProjectConfigurationPlatforms) = postSolution") + $configs + @("`tEndGlobalSection", "`tGlobalSection(NestedProjects) = preSolution") + $nested + @("`tEndGlobalSection", "`tGlobalSection(SharedMSBuildProjectFiles) = preSolution") + $shared + @("`tEndGlobalSection", 'EndGlobal')
    $sourceContent = if ($Clean) { (@($header) + @('Global', 'EndGlobal')) -join "`n" } else { $lines -join "`n" }
    $empty = (@($header) + @('Global', "`tGlobalSection(SolutionConfigurationPlatforms) = preSolution") + @($Model.Settings.configurations | ForEach-Object { $configuration = $_; $Model.Settings.platforms | ForEach-Object { "`t`t$configuration|$_ = $configuration|$_" } }) + @("`tEndGlobalSection", 'EndGlobal')) -join "`n"
    try {
        [IO.File]::WriteAllText($source, $sourceContent, [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText($target, $(if ($null -ne $original) { $original } else { $empty }), [Text.UTF8Encoding]::new($false))
        $arguments = @('sync', $source, $target, '--owner', 'ProjectTools', '--apply', '--json')
        # The component contract explicitly selects these project identities for migration.
        if (-not $Clean) {
            foreach ($project in $Projects) { $arguments += @('--adopt', $project.Guid) }
        }
        $result = & $Executable @arguments
        if ($LASTEXITCODE -ne 0) { throw "SolutionInjector sync failed: $result" }
        $report = $result | ConvertFrom-Json
        if ($report.schemaVersion -ne 1 -or -not $report.applied -or $report.blocked) { throw 'Unsupported or blocked SolutionInjector sync report.' }
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
                $folderGuids = @($templateFolders.Keys | ForEach-Object { Get-ProjectToolsGuid ('ProjectTools.SolutionFolder:' + $_) })
                $folderGuids += Get-ProjectToolsGuid 'ProjectTools.SolutionFolder:!Repository'
                $content = Remove-ProjectToolsEmptyFolders $content $folderGuids
            } else {
                $rootGuid = Get-ProjectToolsGuid ('ProjectTools.SolutionFolder:' + $rootName)
                $technologyGuid = if ($Model.Profile -eq 'udk') { Get-ProjectToolsGuid 'UDK.SolutionFolder:Projects/MsBuild' } else { $rootGuid }
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
        if ($null -ne $original -and -not $report.changed -and $content -ceq $syncContent) { return }
        if ($content -cne $original) { return [pscustomobject]@{ Path = $solution; RelativePath = $Model.Settings.solution; Content = $content; Original = $original } }
    } finally {
        foreach ($file in Get-ChildItem -LiteralPath $directory -File | Where-Object Name -like ($token + '*')) { Remove-Item -LiteralPath $file.FullName }
    }
}