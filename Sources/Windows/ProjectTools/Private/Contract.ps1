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
        $regex = '^' + [regex]::Escape($pattern).Replace('\*\*/', '(?:.*/)?').Replace('\*\*', '.*').Replace('\*', '[^/]*').Replace('\?', '[^/]') + '$'
        foreach ($file in Get-ChildItem -LiteralPath $searchRoot -File -Recurse -ErrorAction Stop | Sort-Object FullName) {
            $relative = $file.FullName.Substring($Root.Length + 1).Replace('\', '/')
            if ($relative -match '/(?:\.git|!artifacts|!tools|bin|obj)/') { continue }
            if ($relative -cmatch $regex) { [void]$selected.Add($relative) }
        }
    }
    foreach ($exclude in $Excludes) {
        $null = Resolve-ProjectToolsPath $Root ($exclude.Replace('*', '_').Replace('?', '_'))
        $regex = '^' + [regex]::Escape($exclude).Replace('\*\*/', '(?:.*/)?').Replace('\*\*', '.*').Replace('\*', '[^/]*').Replace('\?', '[^/]') + '$'
        foreach ($file in @($selected)) { if ($file -cmatch $regex) { [void]$selected.Remove($file) } }
    }
    return @($selected)
}

function Read-ProjectToolsModel([string]$ManifestPath) {
    $path = (Resolve-Path -LiteralPath $ManifestPath -ErrorAction Stop).Path
    $root = Split-Path -Parent $path
    $manifest = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if (($manifest.schemaVersion -isnot [int] -and $manifest.schemaVersion -isnot [long]) -or $manifest.schemaVersion -notin @(2, 3)) { throw 'Unsupported component schemaVersion.' }
    if ($manifest.includes -isnot [Array] -or -not $manifest.includes.Count) { throw 'includes must be a nonempty array.' }
    foreach ($field in $manifest.PSObject.Properties.Name) { if ($field -notin @('schemaVersion', 'includes', 'generation')) { throw "Unknown manifest field: $field" } }
    $settings = $manifest.generation.msbuild
    $profile = $manifest.generation.profile
    if (-not $profile -and $manifest.schemaVersion -eq 2) { $profile = 'udk' }
    if ($profile -and $profile -ne 'udk') { throw "Unknown generation profile: $profile" }
    if (-not $settings) {
        if ($profile -ne 'udk') { throw 'generation.msbuild is required.' }
        $settings = [pscustomobject]@{ solution = 'UniversalDevKit.sln'; projectDirectory = 'Projects/MsBuild/{name}'; projectName = 'UniversalDevKit.{name}.{variant}'; configurations = @('Debug', 'Release'); platforms = @('x64'); solutionFolder = 'Projects' }
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
    $names = @{}
    $guids = @{}
    foreach ($include in $manifest.includes) {
        $componentPath = Resolve-ProjectToolsPath $root $include
        if ($components.Contains($include)) { throw "Duplicate include: $include" }
        $component = Get-Content -LiteralPath $componentPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($component.name -notmatch '^[A-Z][A-Za-z0-9]*$' -or $names.ContainsKey($component.name)) { throw "Invalid or duplicate component name: $($component.name)" }
        $names[$component.name] = $true
        foreach ($field in $component.PSObject.Properties.Name) {
            if ($field -notin @('name', 'msbuildGuid', 'headers', 'sources', 'filters', 'dependencies', 'supportedPlatforms', 'platformSources', 'stateScope', 'requirements', 'platformRequirements', 'buildExtensions', 'compile', 'sourceSettings', 'kind', 'variants', 'excludeHeaders', 'excludeSources', 'msbuild')) { throw "Unknown component field: $field" }
        }
        if (-not $component.kind) { $component | Add-Member kind 'compiled' }
        if ($component.kind -notin @('compiled', 'headerOnly')) { throw 'Invalid component kind.' }
        if (-not $profile -and ($component.platformSources -or $component.platformRequirements -or $component.sourceSettings)) { throw 'Standalone MSBuild generation does not yet support platformSources, platformRequirements or sourceSettings. Use explicit build extensions.' }
        if ($component.PSObject.Properties['variants'] -and ($component.variants -isnot [Array] -or ($component.kind -eq 'compiled' -and -not $component.variants.Count))) { throw 'Compiled variants must be a nonempty array.' }
        foreach ($extensionEntry in $component.buildExtensions.PSObject.Properties) {
            if ($extensionEntry.Name -notin @('cmake', 'msbuildProps', 'msbuildTargets')) { throw 'Unknown build extension.' }
            $extension = Resolve-ProjectToolsPath $root $extensionEntry.Value
            if (-not (Test-Path -LiteralPath $extension -PathType Leaf)) { throw "Missing build extension: $($extensionEntry.Value)" }
        }
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
        if (-not $component.msbuildGuid) { $component | Add-Member msbuildGuid (Get-ProjectToolsGuid ('ProjectTools:' + $component.name + ':Shared')) }
        $parsedGuid = [Guid]::Empty
        if (-not [Guid]::TryParse($component.msbuildGuid, [ref]$parsedGuid) -or $guids.ContainsKey($parsedGuid.ToString())) { throw 'Invalid or duplicate component GUID.' }
        $guids[$parsedGuid.ToString()] = $true
        if ($component.kind -eq 'headerOnly' -and ($component.sources.Count -or $component.platformSources -or $component.variants)) { throw 'Header-only component cannot have sources or binary variants.' }
        $components[$include] = $component
    }
    return [pscustomobject]@{ Root = $root; Manifest = $manifest; Components = $components; Settings = $settings; Profile = $profile }
}