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
        if (-not [Guid]::TryParse($match.Groups[3].Value, [ref]$guid)) {
            throw 'Invalid Shared-project GUID in solution.'
        }
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

function UpdateSolutionSharedReferences([string]$Path, [Guid]$ConsumerGuid, $RemoveProjects, $AddProjects, [scriptblock]$WriteStatus) {
    $original = [IO.File]::ReadAllText($Path)
    $newline = if ($original.Contains("`r`n")) {
        "`r`n"
    } else {
        "`n"
    }
    $consumerKey = $ConsumerGuid.ToString().ToLowerInvariant()
    $lines = [Collections.Generic.List[string]]::new()
    foreach ($project in $AddProjects) {
        $lines.Add($project.SolutionRelativePath + '*{' + $consumerKey + '}*SharedItemsImports = 4')
    }
    $sectionPattern = '(?ms)^(\tGlobalSection\(SharedMSBuildProjectFiles\) = preSolution\r?\n)(.*?)(^\tEndGlobalSection)'
    if (-not [regex]::IsMatch($original, $sectionPattern)) {
        if (-not $AddProjects.Count) {
            return
        }
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
        & $WriteStatus "Updated: $Path" Mark
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