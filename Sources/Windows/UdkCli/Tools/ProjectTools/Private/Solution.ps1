function Get-ProjectToolsSolutionUpdate($Model, $Projects, [string]$Executable) {
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
    $rootName = if ($Model.Settings.solutionFolder) { $Model.Settings.solutionFolder } else { 'Projects' }
    $rootFolderGuid = FindFolderGuid $rootName '' ('ProjectTools.SolutionFolder:' + $rootName)
    $lines += @(('Project("' + $folderType + '") = "' + $rootName + '", "' + $rootName + '", "' + $rootFolderGuid + '"'), 'EndProject')
    $msbuildGuid = FindFolderGuid 'MsBuild' $rootFolderGuid 'UDK.SolutionFolder:Projects/MsBuild'
    if ($Model.Profile -eq 'udk') { $lines += @(('Project("' + $folderType + '") = "MsBuild", "MsBuild", "' + $msbuildGuid + '"'), 'EndProject') }
    if ($Model.Profile -eq 'udk') { $nested += "`t`t$msbuildGuid = $rootFolderGuid" }
    $technologyGuid = if ($Model.Profile -eq 'udk') { $msbuildGuid } else { $rootFolderGuid }
    foreach ($project in $Projects) {
        $name = [IO.Path]::GetFileNameWithoutExtension($project.Path)
        $relative = Get-ProjectToolsRelativePath $directory (Join-Path $Model.Root $project.Path)
        $group = if ($project.Component -in $applicationNames) { 'Application' } else { 'Library' }
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
    $sourceContent = $lines -join "`n"
    $empty = (@($header) + @('Global', "`tGlobalSection(SolutionConfigurationPlatforms) = preSolution") + @($Model.Settings.configurations | ForEach-Object { $configuration = $_; $Model.Settings.platforms | ForEach-Object { "`t`t$configuration|$_ = $configuration|$_" } }) + @("`tEndGlobalSection", 'EndGlobal')) -join "`n"
    try {
        [IO.File]::WriteAllText($source, $sourceContent, [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText($target, $(if ($null -ne $original) { $original } else { $empty }), [Text.UTF8Encoding]::new($false))
        $arguments = @('sync', $source, $target, '--owner', 'ProjectTools', '--apply', '--json')
        # The component contract explicitly selects these project identities for migration.
        foreach ($project in $Projects) { $arguments += @('--adopt', $project.Guid) }
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
        if ($null -ne $original -and -not $report.changed -and $content -ceq $syncContent) { return }
        if ($content -cne $original) { return [pscustomobject]@{ Path = $solution; RelativePath = $Model.Settings.solution; Content = $content; Original = $original } }
    } finally {
        foreach ($file in Get-ChildItem -LiteralPath $directory -File | Where-Object Name -like ($token + '*')) { Remove-Item -LiteralPath $file.FullName }
    }
}