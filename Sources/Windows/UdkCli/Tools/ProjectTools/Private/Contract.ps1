. (Join-Path $PSScriptRoot '../../ResolveJsonReference.ps1')

function Get-ProjectToolsGuid([string]$Identity) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $bytes = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Identity)) } finally { $sha.Dispose() }
    return '{' + ([Guid]::new([byte[]]$bytes[0..15])).ToString().ToUpperInvariant() + '}'
}

function Get-ProjectToolsRelativePath([string]$Directory, [string]$Path) {
    $baseUri = [Uri]::new($Directory.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar)
    $targetPath = if (Test-Path -LiteralPath $Path -PathType Container) { $Path.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar } else { $Path }
    $relative = [Uri]::UnescapeDataString($baseUri.MakeRelativeUri([Uri]::new($targetPath)).ToString()).Replace('/', '\').TrimEnd('\')
    if (-not $relative) { return '.' }
    return $relative
}

function Resolve-ProjectToolsPath([string]$Root, [string]$Path) {
    if (-not $Path -or $Path -match '[\\:$@%;\r\n]' -or @($Path.Split('/') | Where-Object { $_ -in @('', '.', '..') }).Count) {
        throw "Invalid repository path: $Path"
    }
    $absolute = [IO.Path]::GetFullPath((Join-Path $Root $Path))
    if (-not $absolute.StartsWith($Root.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw "Path outside repository: $Path" }
    return $absolute
}

function ConvertTo-ProjectToolsGlobRegex([string]$Pattern) {
    return '^' + [regex]::Escape($Pattern).Replace('\*\*/', '(?:.*/)?').Replace('\*\*', '.*').Replace('\*', '[^/]*').Replace('\?', '[^/]') + '$'
}

function ConvertTo-ProjectToolsFilterRules([string]$Root, $Rules) {
    if ($Rules -isnot [array]) { throw 'filters must be an array.' }
    foreach ($rule in $Rules) {
        if ($rule -isnot [pscustomobject] -or $rule.path -isnot [string] -or $rule.filter -isnot [string]) {
            throw 'Expected path and filter strings in each filters rule.'
        }
        foreach ($field in $rule.PSObject.Properties.Name) {
            if ($field -cnotin @('path', 'filter', 'preserveTree')) { throw "Unknown filters rule field: $field" }
        }
        if ($rule.PSObject.Properties['preserveTree'] -and $rule.preserveTree -isnot [bool]) {
            throw "Expected boolean preserveTree for filters path: $($rule.path)"
        }
        if ($rule.filter -match '[\\:*?"<>|$@%;\r\n]' -or
            ($rule.filter -ne '' -and @($rule.filter.Split('/') | Where-Object { $_ -in @('', '.', '..') }).Count)) {
            throw "Invalid virtual filter folder: $($rule.filter)"
        }
        $pattern = $rule.path
        $absolute = Resolve-ProjectToolsPath $Root ($pattern.Replace('*', '_').Replace('?', '_'))
        if ($pattern -notmatch '[*?]') {
            if (Test-Path -LiteralPath $absolute -PathType Container) {
                $pattern += '/**/*'
            } elseif (-not (Test-Path -LiteralPath $absolute -PathType Leaf)) {
                throw "Missing file or directory for filters path: $pattern"
            }
        }
        $wildcard = $pattern.IndexOfAny([char[]]'*?')
        $prefix = if ($wildcard -lt 0) { $pattern } else { $pattern.Substring(0, $wildcard) }
        [pscustomobject]@{
            Regex = [regex](ConvertTo-ProjectToolsGlobRegex $pattern)
            BaseLength = $prefix.LastIndexOf('/') + 1
            Folder = $rule.filter
            PreserveTree = [bool]$rule.preserveTree
        }
    }
}

function Get-ProjectToolsFilter([string]$Path, $Rules, [string]$Default = '') {
    for ($index = $Rules.Count - 1; $index -ge 0; $index--) {
        $rule = $Rules[$index]
        if (-not $rule.Regex.IsMatch($Path)) { continue }
        $folder = $rule.Folder
        if ($rule.PreserveTree) {
            $relativeFolder = [IO.Path]::GetDirectoryName($Path.Substring($rule.BaseLength))
            if ($relativeFolder) {
                $folder = if ($folder) { $folder + '/' + $relativeFolder } else { $relativeFolder }
            }
        }
        return $folder.Replace('/', '\')
    }
    return $Default
}

function Expand-ProjectToolsFiles($Root, $Patterns, $Excludes) {
    if ($Patterns -isnot [Array]) { throw 'File selection must be an array.' }
    $selected = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($pattern in $Patterns) {
        if ($pattern -isnot [string]) { throw 'File patterns must be strings.' }
        $null = Resolve-ProjectToolsPath $Root ($pattern.Replace('*', '_').Replace('?', '_'))
        if ($pattern -notmatch '[*?]') {
            if (-not (Test-Path -LiteralPath (Join-Path $Root $pattern) -PathType Leaf)) { throw "Missing file: $pattern" }
            if (-not $selected.Add($pattern)) { throw "Duplicate file: $pattern" }
            continue
        }
        $prefix = $pattern.Substring(0, $pattern.IndexOfAny([char[]]'*?'))
        $directory = $prefix.Substring(0, $prefix.LastIndexOf('/') + 1).TrimEnd('/')
        $searchRoot = if ($directory) { Join-Path $Root $directory } else { $Root }
        $regex = ConvertTo-ProjectToolsGlobRegex $pattern
        foreach ($file in Get-ChildItem -LiteralPath $searchRoot -File -Recurse -ErrorAction Stop | Sort-Object FullName) {
            $relative = $file.FullName.Substring($Root.Length + 1).Replace('\', '/')
            if ($relative -match '/(?:\.git|!artifacts|!tools|bin|obj)/') { continue }
            if ($relative -cmatch $regex) { [void]$selected.Add($relative) }
        }
    }
    foreach ($exclude in $Excludes) {
        $null = Resolve-ProjectToolsPath $Root ($exclude.Replace('*', '_').Replace('?', '_'))
        $regex = ConvertTo-ProjectToolsGlobRegex $exclude
        foreach ($file in @($selected)) { if ($file -cmatch $regex) { [void]$selected.Remove($file) } }
    }
    return @($selected)
}

function Read-ProjectToolsModel([string]$ManifestPath) {
    $path = (Resolve-Path -LiteralPath $ManifestPath -ErrorAction Stop).Path
    $root = Split-Path -Parent $path
    $manifest = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if (($manifest.schemaVersion -isnot [int] -and $manifest.schemaVersion -isnot [long]) -or $manifest.schemaVersion -notin @(2, 3, 4, 5)) { throw 'Unsupported component schemaVersion.' }
    $unified = $manifest.schemaVersion -in @(4, 5)
    $listField = if ($unified) { 'components' } else { 'includes' }
    if ($manifest.$listField -isnot [Array] -or -not $manifest.$listField.Count) { throw "$listField must be a nonempty array." }
    $manifestFields = @('schemaVersion', 'generation', $listField)
    if (-not $unified) { $manifestFields += 'msbuildApplications' }
    foreach ($field in $manifest.PSObject.Properties.Name) { if ($field -notin $manifestFields) { throw "Unknown manifest field: $field" } }
    $settings = $manifest.generation.msbuild
    $profile = $manifest.generation.profile
    if (-not $profile -and $manifest.schemaVersion -eq 2) { $profile = 'udk' }
    if ($profile -and $profile -ne 'udk') { throw "Unknown generation profile: $profile" }
    if (-not $settings) {
        if ($profile -ne 'udk') { throw 'generation.msbuild is required.' }
        $projectDirectory = if ($unified) { 'Projects/MsBuild/{kind}/{name}' } else { 'Projects/MsBuild/{name}' }
        $settings = [pscustomobject]@{ solution = 'UniversalDevKit.sln'; projectDirectory = $projectDirectory; projectName = 'UniversalDevKit.{name}.{variant}'; configurations = @('Debug', 'Release'); platforms = @('x64'); solutionFolder = 'Projects' }
    }
    foreach ($field in $settings.PSObject.Properties.Name) {
        if ($field -notin @('solution', 'projectDirectory', 'projectName', 'configurations', 'platforms', 'solutionFolder', 'props', 'targets')) { throw "Unknown MSBuild generation setting: $field" }
    }
    $null = Resolve-ProjectToolsPath $root $settings.solution
    if ($settings.projectDirectory -notmatch '\{name\}' -or $settings.projectName -notmatch '\{name\}' -or $settings.projectName -notmatch '\{variant\}') { throw 'Project layout must contain {name} and {variant} placeholders.' }
    if ($settings.projectName -match '[/\\]' -or $settings.projectName.Replace('{name}', '').Replace('{variant}', '') -match '[{}]') { throw 'Invalid projectName template.' }
    foreach ($extensionPath in @($settings.props) + @($settings.targets)) {
        if (-not $extensionPath) { continue }
        $extension = Resolve-ProjectToolsPath $root $extensionPath
        if (-not (Test-Path -LiteralPath $extension -PathType Leaf)) { throw "Missing build extension: $extensionPath" }
    }
    foreach ($field in @('configurations', 'platforms')) {
        if ($settings.$field -isnot [Array] -or -not $settings.$field.Count) { throw "$field must be a nonempty array." }
        foreach ($value in $settings.$field) { if ($value -notmatch '^[A-Za-z0-9_.-]+$') { throw "Invalid ${field}: $value" } }
    }
    $components = [ordered]@{}
    $applications = [ordered]@{}
    $managedLibraries = [ordered]@{}
    if ($manifest.PSObject.Properties['msbuildApplications'] -and ($profile -ne 'udk' -or $manifest.msbuildApplications -isnot [Array])) {
        throw 'msbuildApplications must be an array in the UDK profile.'
    }
    $guids = @{}
    $includes = @($manifest.$listField)
    if ($manifest.msbuildApplications) { $includes += $manifest.msbuildApplications }
    $seenIncludes = @{}
    $names = @{}
    $definitions = foreach ($include in $includes) {
        if ($include -isnot [string] -or $include -match '[*?]' -or [IO.Path]::GetExtension($include) -cne '.json') { throw "Invalid component path: $include" }
        $componentPath = Resolve-ProjectToolsPath $root $include
        if ($seenIncludes.ContainsKey($include)) { throw "Duplicate include: $include" }
        $seenIncludes[$include] = $true
        $definition = Get-Content -LiteralPath $componentPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($definition.name -isnot [string] -or $definition.name -cnotmatch '^[A-Z][A-Za-z0-9]*(?:\.[A-Za-z0-9]+)*$' -or $names.ContainsKey($definition.name)) {
            throw "Invalid or duplicate component name: $($definition.name)"
        }
        $names[$definition.name] = $true
        if ($manifest.schemaVersion -ne 5) {
            [pscustomobject]@{ Include = $include; Component = $definition; RuntimeProjects = @() }
            continue
        }
        if (@($definition.PSObject.Properties.Name | Where-Object { $_ -cnotin @('name', 'projects') }).Count -or
            $definition.projects -isnot [Array] -or -not $definition.projects.Count) {
            throw "Expected name and a nonempty projects array: $include"
        }
        $projectIds = @{}
        $projectTypes = @{}
        foreach ($project in $definition.projects) {
            if ($project -isnot [pscustomobject] -or $project.PSObject.Properties['name']) { throw "Invalid project object: $include" }
            $language = switch -CaseSensitive ($project.projectType) {
                'native' { 'cpp' }
                { $_ -cin @('classLibrary', 'wpf', 'vsix') } { 'csharp' }
                default { throw "Unsupported projectType in ${include}: $($project.projectType)" }
            }
            if ($project.PSObject.Properties['language']) {
                throw "Unknown project field 'language' in ${include}."
            }
            $project | Add-Member language $language
            $identity = "$($project.kind)/$($project.language)/$($project.projectType)"
            if ($projectTypes.ContainsKey($identity)) { throw "Duplicate project type $identity in $include" }
            $projectTypes[$identity] = $true
            if ($project.PSObject.Properties['id']) {
                if ($project.id -isnot [string] -or $project.id -cnotmatch '^[A-Za-z][A-Za-z0-9_-]*$' -or $projectIds.ContainsKey($project.id)) {
                    throw "Invalid or duplicate project id in $include"
                }
                $projectIds[$project.id] = $project
            }
        }
        $applicationCount = @($definition.projects | Where-Object kind -ceq 'application').Count
        if ($applicationCount -and $definition.projects.Count -ne 1) { throw "An application component must contain one project: $include" }
        foreach ($project in $definition.projects) {
            $runtimeProjects = @()
            if ($project.PSObject.Properties['runtimeDependencies']) {
                if ($project.language -cne 'csharp' -or $project.projectType -cne 'classLibrary' -or $project.runtimeDependencies -isnot [Array]) {
                    throw "runtimeDependencies requires a C# classLibrary and an array: $include"
                }
                $seenRuntimeIds = @{}
                $runtimeProjects = @(foreach ($dependency in $project.runtimeDependencies) {
                    if ($dependency -isnot [pscustomobject] -or
                        @($dependency.PSObject.Properties.Name | Where-Object { $_ -cnotin @('projectId', 'variant') }).Count -or
                        $dependency.projectId -isnot [string] -or $dependency.variant -cne 'Dynamic' -or
                        -not $projectIds.ContainsKey($dependency.projectId) -or $seenRuntimeIds.ContainsKey($dependency.projectId)) {
                        throw "Invalid runtime dependency in $include. Expected projectId and variant Dynamic."
                    }
                    $seenRuntimeIds[$dependency.projectId] = $true
                    $target = $projectIds[$dependency.projectId]
                    if ($target.kind -cne 'library' -or $target.language -cne 'cpp' -or $target.projectType -cne 'native' -or
                        $target.libraryType -eq 'headerOnly' -or ($target.variants -and 'Dynamic' -notin $target.variants)) {
                        throw "Runtime dependency $($dependency.projectId) must provide a native Dynamic library: $include"
                    }
                    $target
                })
                $project.PSObject.Properties.Remove('runtimeDependencies')
            }
            $project.PSObject.Properties.Remove('id')
            $project | Add-Member name $definition.name
            [pscustomobject]@{ Include = $include; Component = $project; RuntimeProjects = $runtimeProjects }
        }
    }
    foreach ($definition in $definitions) {
        $include = $definition.Include
        $componentPath = Resolve-ProjectToolsPath $root $include
        $component = $definition.Component
        if ($component.PSObject.Properties['githubVersion']) {
            Resolve-UdkDescriptionVersion $root $component $componentPath 'githubVersion'
        }
        Resolve-UdkDescriptionAbiVersion $root $component $componentPath
        $isApplication = $component.kind -ceq 'application'
        if ($unified) {
            if ($component.language -isnot [string] -or $component.projectType -isnot [string]) {
                throw "Expected language and projectType strings: $include"
            }
        } elseif ($component.PSObject.Properties['language'] -or $component.PSObject.Properties['projectType']) {
            throw "language and projectType require schemaVersion 4: $include"
        }
        $isManagedLibrary = $manifest.schemaVersion -eq 5 -and $component.kind -ceq 'library' -and
            $component.language -ceq 'csharp' -and $component.projectType -ceq 'classLibrary'
        $isDotNet = $isManagedLibrary -or ($unified -and $isApplication -and $component.language -ceq 'csharp' -and $component.projectType -cin @('wpf', 'vsix'))
        if (-not $isDotNet -and $component.name -notmatch '^[A-Z][A-Za-z0-9]*$') { throw "Invalid native component name: $($component.name)" }
        if ($unified) {
            if (-not $isDotNet -and ($component.language -cne 'cpp' -or $component.projectType -cne 'native')) {
                throw "Unsupported language and projectType for component: $include"
            }
            if ($component.kind -ceq 'library' -and -not $isManagedLibrary) {
                $libraryType = if ($component.PSObject.Properties['libraryType']) { $component.libraryType } else { 'compiled' }
                if ($libraryType -cnotin @('compiled', 'headerOnly')) { throw "Invalid libraryType: $include" }
                $component.kind = $libraryType
                $component.PSObject.Properties.Remove('libraryType')
            } elseif (-not $isApplication -and -not $isManagedLibrary) { throw "Expected library or application kind: $include" }
        } elseif ($isApplication -ne ($include -in $manifest.msbuildApplications)) {
            throw "Invalid application registration: $include"
        }
        if ($isDotNet) {
            if ($component.PSObject.Properties['version']) {
                $version = $null
                if ($component.projectType -cne 'vsix' -or $component.version -isnot [string] -or
                    $component.version -cnotmatch '\A[0-9]+\.[0-9]+\.[0-9]+(?:\.[0-9]+)?\z' -or
                    -not [Version]::TryParse($component.version, [ref]$version)) {
                    throw "Expected a numeric version with three or four parts for a VSIX project: $include"
                }
            }
            foreach ($field in $component.PSObject.Properties.Name) {
                if ($field -notin @('name', 'kind', 'language', 'projectType', 'githubVersion', 'version', 'abiVersion', 'msbuildGuid', 'msbuild', 'buildExtensions', 'filters', 'sources', 'excludeSources')) { throw "Unsupported C# application field: $field" }
            }
            foreach ($field in $component.msbuild.PSObject.Properties.Name) {
                if ($field -ne 'properties') { throw "Unsupported C# MSBuild setting: $field" }
            }
            $framework = $component.msbuild.properties.TargetFramework
            if ($isManagedLibrary -and ($framework -isnot [string] -or $framework -cnotmatch '^net(?:standard|coreapp)?[0-9]+(?:\.[0-9]+)*(?:-[a-z]+[0-9.]*)?$')) {
                throw "C# classLibrary requires TargetFramework in msbuild.properties: $include"
            }
            if ($component.projectType -eq 'wpf' -and ($framework -isnot [string] -or $framework -cnotmatch '^net[0-9]+\.[0-9]+-windows(?:[0-9]+(?:\.[0-9]+)*)?$')) {
                throw "WPF requires a Windows TargetFramework in msbuild.properties: $include"
            }
            if ($component.projectType -eq 'vsix' -and ($framework -isnot [string] -or $framework -cne 'net472')) {
                throw "VSIX requires TargetFramework net472 in msbuild.properties: $include"
            }
            $component.sources = @(Expand-ProjectToolsFiles $root $component.sources $component.excludeSources)
            $extensions = if ($component.projectType -eq 'wpf') { @('.cs', '.xaml') } else { @('.cs') }
            foreach ($file in $component.sources) {
                if ([IO.Path]::GetExtension($file) -notin $extensions) { throw "Unsupported C# source file: $file" }
            }
            if ($component.projectType -eq 'wpf' -and @($component.sources | Where-Object { [IO.Path]::GetFileName($_) -ieq 'App.xaml' }).Count -gt 1) {
                throw "Expected at most one WPF App.xaml in sources: $include"
            }
        } else {
            foreach ($field in $component.PSObject.Properties.Name) {
                if ($field -notin @('name', 'githubVersion', 'abiVersion', 'msbuildGuid', 'headers', 'sources', 'filters', 'dependencies', 'supportedPlatforms', 'platformSources', 'stateScope', 'requirements', 'platformRequirements', 'buildExtensions', 'compile', 'sourceSettings', 'kind', 'language', 'projectType', 'variants', 'excludeHeaders', 'excludeSources', 'msbuild')) { throw "Unknown component field: $field" }
            }
            if (-not $component.kind) { $component | Add-Member kind 'compiled' }
            if ($isApplication) {
                foreach ($field in $component.PSObject.Properties.Name) {
                    if ($field -notin @('name', 'kind', 'language', 'projectType', 'githubVersion', 'abiVersion', 'msbuildGuid', 'headers', 'sources', 'excludeHeaders', 'excludeSources', 'filters', 'requirements', 'compile', 'buildExtensions', 'msbuild')) {
                        throw "Unsupported application field: $field"
                    }
                }
                foreach ($field in $component.requirements.PSObject.Properties.Name) {
                    if ($field -ne 'cxxStandard') { throw "Unsupported application requirement: $field" }
                }
                foreach ($field in $component.compile.PSObject.Properties.Name) {
                    if ($field -ne 'includeDirectories') { throw "Unsupported application compile setting: $field" }
                }
                foreach ($field in $component.msbuild.PSObject.Properties.Name) {
                    if ($field -ne 'properties') { throw "Unsupported application MSBuild setting: $field" }
                }
            } elseif ($component.kind -notin @('compiled', 'headerOnly')) { throw 'Invalid library component kind.' }
            if (-not $profile -and ($component.platformSources -or $component.platformRequirements -or $component.sourceSettings)) { throw 'Standalone MSBuild generation does not yet support platformSources, platformRequirements or sourceSettings. Use explicit build extensions.' }
            if ($component.PSObject.Properties['variants'] -and ($component.variants -isnot [Array] -or ($component.kind -eq 'compiled' -and -not $component.variants.Count))) { throw 'Compiled variants must be a nonempty array.' }
            foreach ($field in $component.msbuild.PSObject.Properties.Name) { if ($field -notin @('properties', 'dynamicDefinitions', 'resolvedFiles')) { throw "Unknown component MSBuild setting: $field" } }
            foreach ($field in $component.compile.PSObject.Properties.Name) { if ($field -notin @('includeDirectories', 'preprocessorDefinitions', 'precompiledHeader')) { throw "Unknown compile setting: $field" } }
            if ($component.requirements.cxxStandard -and $component.requirements.cxxStandard -notin @(20, 23)) { throw 'Supported C++ standards are 20 and 23.' }
            foreach ($dependency in $component.dependencies) {
                if ($dependency.visibility -notin @('public', 'private') -or $dependency.linkage -notin @('same', 'static', 'dynamic')) { throw 'Invalid dependency visibility/linkage.' }
            }
            foreach ($field in @('headers', 'sources')) {
                $exclude = if ($field -eq 'headers') { $component.excludeHeaders } else { $component.excludeSources }
                $component.$field = @(Expand-ProjectToolsFiles $root $component.$field $exclude)
            }
            foreach ($entry in $component.platformSources.PSObject.Properties) { $entry.Value = @(Expand-ProjectToolsFiles $root $entry.Value @()) }
        }
        if ($component.PSObject.Properties['filters']) {
            $component.filters = @(ConvertTo-ProjectToolsFilterRules $root $component.filters)
        }
        foreach ($extensionEntry in $component.buildExtensions.PSObject.Properties) {
            if ($extensionEntry.Name -notin @('cmake', 'msbuildProps', 'msbuildTargets')) { throw 'Unknown build extension.' }
            if (($isApplication -or $isManagedLibrary) -and $extensionEntry.Name -eq 'cmake') { throw 'This project supports MSBuild extensions only.' }
            $extension = Resolve-ProjectToolsPath $root $extensionEntry.Value
            if (-not (Test-Path -LiteralPath $extension -PathType Leaf)) { throw "Missing build extension: $($extensionEntry.Value)" }
        }
        if (-not $component.msbuildGuid) {
            $identity = if ($isManagedLibrary) { 'ClassLibrary' } elseif ($isApplication) { 'Application' } else { 'Shared' }
            $component | Add-Member msbuildGuid (Get-ProjectToolsGuid ('ProjectTools:' + $component.name + ':' + $identity))
        }
        $parsedGuid = [Guid]::Empty
        if (-not [Guid]::TryParse($component.msbuildGuid, [ref]$parsedGuid) -or $guids.ContainsKey($parsedGuid.ToString())) { throw 'Invalid or duplicate component GUID.' }
        $guids[$parsedGuid.ToString()] = $true
        if ($component.kind -eq 'headerOnly' -and ($component.sources.Count -or $component.platformSources -or $component.variants)) { throw 'Header-only component cannot have sources or binary variants.' }
        if ($isManagedLibrary) {
            $component | Add-Member runtimeProjects $definition.RuntimeProjects
            $managedLibraries[$include] = $component
        }
        elseif ($isApplication) { $applications[$include] = $component }
        else { $components[$include] = $component }
    }
    return [pscustomobject]@{ Root = $root; Manifest = $manifest; Components = $components; Applications = $applications; ManagedLibraries = $managedLibraries; Settings = $settings; Profile = $profile }
}