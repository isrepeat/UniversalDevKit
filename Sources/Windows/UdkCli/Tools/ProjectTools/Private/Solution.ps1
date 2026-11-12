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
    $folderNames = @{}
    function FindFolderGuid([string]$Name, [string]$Parent, [string]$Identity) {
        foreach ($match in [regex]::Matches($original, 'Project\("\{2150E333-8FDC-42A3-9474-1A3956D46DE8\}"\) = "' + [regex]::Escape($Name) + '", "[^"]+", "(\{[^}]+\})"')) {
            $candidate = $match.Groups[1].Value
            if (-not $Parent -or $original -match ([regex]::Escape($candidate) + '\s*=\s*' + [regex]::Escape($Parent))) { return $candidate }
        }
        return Get-ProjectToolsGuid $Identity
    }
    $rootName = if ($Model.Settings.solutionFolder) { $Model.Settings.solutionFolder } else { 'Projects' }
    $rootFolderGuid = FindFolderGuid $rootName '' ('ProjectTools.SolutionFolder:' + $rootName)
    $lines += @(('Project("' + $folderType + '") = "' + $rootName + '", "' + $rootName + '", "' + $rootFolderGuid + '"'), 'EndProject')
    $msbuildGuid = FindFolderGuid 'MsBuild' $rootFolderGuid 'UDK.SolutionFolder:Projects/MsBuild'
    if ($Model.Profile -eq 'udk') { $lines += @(('Project("' + $folderType + '") = "MsBuild", "MsBuild", "' + $msbuildGuid + '"'), 'EndProject') }
    if ($Model.Profile -eq 'udk') { $nested += "`t`t$msbuildGuid = $rootFolderGuid" }
    foreach ($project in $Projects) {
        $folderName = $project.Component
        $parentGuid = if ($Model.Profile -eq 'udk') { $msbuildGuid } else { $rootFolderGuid }
        $folderGuid = FindFolderGuid $folderName $parentGuid ('UDK.SolutionFolder:Projects/MsBuild/' + $folderName)
        if (-not $folderNames.ContainsKey($folderName)) {
            $folderNames[$folderName] = $folderGuid
            if ($Model.Profile -eq 'udk') { $nested += "`t`t$folderGuid = $msbuildGuid" }
            else { $nested += "`t`t$folderGuid = $rootFolderGuid" }
            $lines += @(('Project("' + $folderType + '") = "' + $folderName + '", "' + $folderName + '", "' + $folderGuid + '"'), 'EndProject')
        }
        $name = [IO.Path]::GetFileNameWithoutExtension($project.Path)
        $relative = Get-ProjectToolsRelativePath $directory (Join-Path $Model.Root $project.Path)
        $lines += @(('Project("' + $projectType + '") = "' + $name + '", "' + $relative + '", "' + $project.Guid + '"'), 'EndProject')
        $nested += "`t`t$($project.Guid) = $folderGuid"
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
        if ($null -ne $original -and -not $report.changed) { return }
        if ($content -cne $original) { return [pscustomobject]@{ Path = $solution; RelativePath = $Model.Settings.solution; Content = $content; Original = $original } }
    } finally {
        foreach ($file in Get-ChildItem -LiteralPath $directory -File | Where-Object Name -like ($token + '*')) { Remove-Item -LiteralPath $file.FullName }
    }
}