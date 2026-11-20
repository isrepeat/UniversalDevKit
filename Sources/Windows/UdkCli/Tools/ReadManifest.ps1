function Resolve-UdkManifestPath([string]$Path) {
    $extension = [IO.Path]::GetExtension($Path)
    if ($extension -eq '.json') {
        throw "JSON manifests are unsupported. Use XML: $Path"
    }
    if ($extension -ne '.xml') {
        $Path += '.xml'
    }
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        return (Resolve-Path -LiteralPath $Path).Path
    }
    throw "Missing manifest: $Path"
}

function Get-UdkPackageManifests([string]$Root) {
    Get-ChildItem -LiteralPath $Root -Recurse -File -Filter 'Package.xml' | Sort-Object FullName
}

function Get-UdkOutputExtension([string]$Role) {
    switch -CaseSensitive ($Role) {
        { $_ -cin @('project-nativeLibrary', 'project-nativeApplication', 'project-headerCheck', 'project-winrt') } { 'vcxproj' }
        { $_ -cin @('project-classLibrary', 'project-wpf', 'project-vsix', 'project-winui', 'project-winrtProjection') } { 'csproj' }
        'shared-items' { 'vcxitems' }
        { $_ -cin @('core-exportHeader', 'component-exportHeader', 'version-header') } { 'g.h' }
        { $_ -cin @('dependencies-props', 'version-props') } { 'g.props' }
        'source-headerCheck' { 'g.cpp' }
        'sourceIntegration-targets' { 'g.targets' }
        default { throw "Unknown output role: $Role" }
    }
}

function Assert-UdkExtensionScope([System.Xml.XmlElement]$Owner, [switch]$Expanded) {
    $backends = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($extension in $Owner.SelectNodes('*[not(self::Projects)]/descendant-or-self::Extension')) {
        $backend = $extension.GetAttribute('backend')
        if ($extension.ParentNode -ne $Owner -or $Owner.Name -cnotin @('Project', 'ComponentRegistry') -or
            $backend -cnotin @('MSBuild', 'CMake') -or ($Owner.Name -ceq 'ComponentRegistry' -and $backend -cne 'MSBuild') -or
            $extension.Attributes.Count -ne 1 -or -not $backends.Add($backend) -or
            $extension.SelectSingleNode('text()[normalize-space()]')) {
            throw "Invalid Extension backend or placement: $backend"
        }
        $allowed = if ($backend -ceq 'MSBuild' -and $Owner.Name -ceq 'Project') {
            @('Files', 'Filters', 'Properties', 'DynamicDefinitions', 'ProjectName', 'ProjectNames', 'ProjectDirectory', 'SolutionFolder')
        } else { @('Files') }
        foreach ($child in $extension.SelectNodes('*')) {
            if ($child.Name -cnotin $allowed -or $extension.SelectNodes($child.Name).Count -ne 1) {
                throw "Invalid or duplicate element in Extension backend=${backend}: $($child.Name)"
            }
        }
        $files = $extension.SelectSingleNode('Files')
        if ($files -and ($files.Attributes.Count -or $files.SelectSingleNode('text()[normalize-space()]') -or
            $files.SelectSingleNode('.//*[not(self::Group or self::Input or self::File or self::Ref or self::Output)]') -or
            ($backend -cne 'MSBuild' -and $files.SelectSingleNode('.//Output')))) {
            throw "Invalid Files in Extension backend=$backend"
        }
    }
    $inputPath = 'Files//Input|Extension/Files//Input'
    if (-not $Expanded) { $inputPath += '|Filters//Input|Extension/Filters//Input' }
    foreach ($inputFile in $Owner.SelectNodes($inputPath)) {
        $role = $inputFile.GetAttribute('role')
        $extension = $inputFile.SelectSingleNode('ancestor::Extension')
        $requiredBackend = switch -CaseSensitive ($role) {
            'cmake' { 'CMake' }
            'msbuild-props' { 'MSBuild' }
            'msbuild-targets' { 'MSBuild' }
        }
        if (($requiredBackend -and (-not $extension -or $extension.GetAttribute('backend') -cne $requiredBackend)) -or
            ($extension -and -not $requiredBackend)) {
            throw "Input role '$role' is invalid here. Expected backend: $requiredBackend"
        }
        if ($Owner.Name -ceq 'ComponentRegistry' -and $extension -and
            ($role -cne 'msbuild-props' -or $inputFile.GetAttribute('projectType') -cne 'native')) {
            throw 'Registry extensions support only native msbuild-props.'
        }
    }
    if ($Owner.SelectSingleNode('Files//*[self::CMake or self::MSBuildProps or self::MSBuildTargets]')) {
        throw 'Use backend-specific Input roles in Extension Files.'
    }
}

function Convert-UdkFileScope([System.Xml.XmlElement]$Owner, $ParentScope) {
    Assert-UdkExtensionScope $Owner
    if ($Owner.Name -ceq 'Project' -and $Owner.SelectSingleNode('MSBuild|BuildExtensions')) {
        throw 'Declare project build settings in Extension.'
    }
    $scope = [pscustomobject]@{
        Parent = $ParentScope
        Nodes = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
        Outputs = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
        Inputs = @()
    }
    foreach ($node in $Owner.SelectNodes('*[not(self::Projects)]/descendant-or-self::*[@id]')) {
        if ($node.LocalName -ceq 'Ref') { continue }
        $id = $node.GetAttribute('id')
        $key = "$($node.LocalName):$id"
        if ($id -cnotmatch '^[A-Za-z][A-Za-z0-9_.-]*$' -or $scope.Nodes.ContainsKey($key)) {
            throw "Invalid or duplicate file declaration: $key"
        }
        $scope.Nodes.Add($key, $node.CloneNode($true))
    }
    foreach ($node in $Owner.SelectNodes('Files//Output|Extension/Files//Output')) {
        $role = $node.GetAttribute('role')
        $null = Get-UdkOutputExtension $role
        $template = $node.InnerText.Trim()
        if ($node.SelectSingleNode('*') -or @($node.Attributes | Where-Object Name -CNotIn @('role', 'id')).Count -or
            -not $template.EndsWith('.{ext}', [StringComparison]::Ordinal) -or $scope.Outputs.ContainsKey($role)) {
            throw "Invalid or duplicate output template: $role"
        }
        $scope.Outputs.Add($role, $template)
    }
    function ExpandRefs($Node, $DefinitionScope, [object[]]$Stack) {
        foreach ($child in @($Node.SelectNodes('*[not(self::Projects)]'))) {
            if ($child.LocalName -cne 'Ref') {
                ExpandRefs $child $DefinitionScope $Stack
                continue
            }
            $key = "$($child.GetAttribute('tag')):$($child.GetAttribute('id'))"
            if ($child.Attributes.Count -ne 2 -or $child.SelectSingleNode('*') -or $child.InnerText.Trim()) {
                throw "Invalid Ref: $key"
            }
            $targetScope = $DefinitionScope
            while ($targetScope -and -not $targetScope.Nodes.ContainsKey($key)) { $targetScope = $targetScope.Parent }
            if (-not $targetScope) { throw "Unknown Ref: $key" }
            $target = $targetScope.Nodes[$key]
            if ($target -in $Stack) { throw "Cyclic Ref: $key" }
            $copy = $Node.OwnerDocument.ImportNode($target, $true)
            ExpandRefs $copy $targetScope ($Stack + @($target))
            [void]$Node.ReplaceChild($copy, $child)
        }
    }
    ExpandRefs $Owner $scope @()
    # Filter references may point to backend files for display.
    Assert-UdkExtensionScope $Owner -Expanded
    foreach ($extension in @($Owner.SelectNodes('Extension'))) {
        $extensionFiles = $extension.SelectSingleNode('Files')
        if ($extensionFiles) {
            $files = $Owner.SelectSingleNode('Files')
            if (-not $files) {
                $files = $Owner.OwnerDocument.CreateElement('Files')
                [void]$Owner.InsertBefore($files, $extension)
            }
            foreach ($entry in @($extensionFiles.SelectNodes('*'))) { [void]$files.AppendChild($entry) }
            [void]$extension.RemoveChild($extensionFiles)
        }
        $extensionFilters = $extension.SelectSingleNode('Filters')
        if ($extensionFilters) {
            $filters = $Owner.SelectSingleNode('Filters')
            if (-not $filters) {
                $filters = $Owner.OwnerDocument.CreateElement('Filters')
                [void]$Owner.InsertBefore($filters, $extension)
            }
            if ($extensionFilters.Attributes.Count -or $extensionFilters.SelectSingleNode('text()[normalize-space()]')) {
                throw 'Invalid Filters in Extension backend=MSBuild'
            }
            foreach ($filter in @($extensionFilters.SelectNodes('*'))) { [void]$filters.AppendChild($filter) }
            [void]$extension.RemoveChild($extensionFilters)
        }
        if ($extension.SelectSingleNode('*')) {
            $msbuild = $Owner.OwnerDocument.CreateElement('MSBuild')
            foreach ($entry in @($extension.SelectNodes('*'))) { [void]$msbuild.AppendChild($entry) }
            [void]$Owner.InsertBefore($msbuild, $extension)
        }
        [void]$Owner.RemoveChild($extension)
    }
    $scope.Inputs = @($Owner.SelectNodes('Files//Input') | ForEach-Object { $_.CloneNode($true) })
    foreach ($node in @($Owner.SelectNodes('Files//Input|Filters//Input|Files//Output|Filters//Output'))) {
        $role = $node.GetAttribute('role')
        $value = $node.InnerText.Trim()
        if ($node.Name -ceq 'Output') {
            $tag = 'Output'
            $value = '@output:' + $role
        } else {
            if ($node.SelectSingleNode('*') -or -not $value -or
                @($node.Attributes | Where-Object Name -CNotIn @('id', 'role', 'projectType')).Count) {
                throw "Invalid input declaration: $role"
            }
            $tag = switch -CaseSensitive ($role) {
                'header' { 'Header' }
                'source' { 'Source' }
                'cmake' { 'CMake' }
                'msbuild-props' { 'MSBuildProps' }
                'msbuild-targets' { 'MSBuildTargets' }
                'version-source' { 'File' }
                default { throw "Unknown input role: $role" }
            }
            if ($Owner.Name -ceq 'ComponentRegistry') { $tag = 'File' }
        }
        $replacement = $Owner.OwnerDocument.CreateElement($tag)
        $replacement.InnerText = $value
        [void]$node.ParentNode.ReplaceChild($replacement, $node)
    }
    foreach ($node in $Owner.SelectNodes('Files//File[@id]|Filters//File[@id]')) {
        $node.RemoveAttribute('id')
    }
    foreach ($node in $Owner.SelectNodes('Files//Group[@id]|Filters//Group[@id]')) {
        $node.SetAttribute('name', $node.GetAttribute('id'))
        $node.RemoveAttribute('id')
    }
    return $scope
}

function Convert-UdkComponentFiles([System.Xml.XmlElement]$Owner) {
    $files = $Owner.SelectSingleNode('Files')
    if (-not $files) {
        return
    }
    if ($Owner.SelectSingleNode('Headers|Sources|BuildExtensions') -or $files.Attributes.Count -or
        $files.SelectSingleNode('text()[normalize-space()]')) {
        throw 'Files must contain declarations and replaces Headers, Sources and BuildExtensions.'
    }
    $document = $Owner.OwnerDocument
    $filters = $Owner.SelectSingleNode('Filters')
    $groups = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    $selections = [Collections.Generic.List[object]]::new()
    function ReadFileDeclarations($Parent) {
        foreach ($file in $Parent.SelectNodes('*')) {
            if ($file.LocalName -ceq 'Group') {
                ReadFileDeclarations $file
                continue
            }
            if ($file.Name -cnotin @('Header', 'Source', 'File', 'Output', 'Generated', 'CMake', 'MSBuildProps', 'MSBuildTargets') -or
                $file.Attributes.Count -or $file.SelectSingleNode('*') -or -not $file.InnerText.Trim()) {
                throw "Invalid file declaration: $($file.Name)"
            }
            $file
        }
    }
    foreach ($node in $files.SelectNodes('*')) {
        if ($node.LocalName -ceq 'Group') {
            $name = $node.GetAttribute('name')
            if ($name -cnotmatch '^[A-Za-z][A-Za-z0-9_.-]*$' -or $node.Attributes.Count -ne 1 -or
                $groups.ContainsKey($name) -or $node.SelectSingleNode('text()[normalize-space()]')) {
                throw "Invalid or duplicate Files group: $name"
            }
            $entries = @(ReadFileDeclarations $node)
            if (-not $entries.Count) { throw "Empty Files group: $name" }
            $groups.Add($name, $entries)
            $selections.AddRange($entries)
        } else {
            $container = $document.CreateElement('Files')
            [void]$container.AppendChild($node.CloneNode($true))
            $selections.Add((ReadFileDeclarations $container))
        }
    }
    $buckets = @{ Header = 'Headers'; Source = 'Sources'; CMake = 'BuildExtensions'; MSBuildProps = 'BuildExtensions'; MSBuildTargets = 'BuildExtensions' }
    $legacyProject = $Owner.LocalName -ceq 'Component' -and -not $Owner.SelectSingleNode('Projects') -and
        $Owner.SelectSingleNode('Kind|ProjectGuid')
    if ($Owner.LocalName -ceq 'Project' -or $legacyProject) {
        $buckets['File'] = 'BrowseFiles'
    }
    foreach ($file in $selections) {
        $bucket = $buckets[$file.Name]
        if ($bucket) {
            $target = $Owner.SelectSingleNode($bucket)
            if (-not $target) {
                $target = $document.CreateElement($bucket)
                [void]$Owner.InsertBefore($target, $files)
            }
            [void]$target.AppendChild($file.CloneNode($true))
        }
    }
    if ($Owner.GetAttribute('projectType') -cin @('native', 'winrt') -or $legacyProject) {
        foreach ($bucket in 'Headers', 'Sources') {
            if (-not $Owner.SelectSingleNode($bucket)) {
                [void]$Owner.InsertBefore($document.CreateElement($bucket), $files)
            }
        }
    }
    [void]$Owner.RemoveChild($files)
    if (-not $filters) { return }
    foreach ($filter in @($filters.SelectNodes('*'))) {
        $destination = [regex]::Match($filter.GetAttribute('filter'), '^\{Tree:(Project|Solution)\}(?:/(.+))?$')
        if ($filter.Name -cne 'Filter' -or -not $destination.Success -or $filter.SelectSingleNode('text()[normalize-space()]') -or
            @($filter.Attributes | Where-Object Name -CNotIn @('filter', 'preserveTree')).Count) {
            throw 'Expected Filter with an explicit {Tree:Project} or {Tree:Solution} destination.'
        }
        $solution = $destination.Groups[1].Value -ceq 'Solution'
        $folder = $destination.Groups[2].Value
        if ($solution -and -not $folder) { throw 'A solution filter requires a virtual folder.' }
        foreach ($selector in $filter.SelectNodes('*')) {
            $value = $selector.InnerText.Trim()
            $entries = switch -CaseSensitive ($selector.LocalName) {
                'Group' { ReadFileDeclarations $selector }
                'GroupRef' {
                    if ($selector.Attributes.Count -or $selector.SelectSingleNode('*')) { throw 'Invalid GroupRef.' }
                    if (-not $groups.ContainsKey($value)) { throw "Unknown Files group: $value" }
                    $groups[$value]
                }
                'Match' {
                    if (-not $value -or $selector.Attributes.Count -or $selector.SelectSingleNode('*')) { throw 'Invalid Match.' }
                    $selections
                }
                default {
                    $container = $document.CreateElement('Files')
                    [void]$container.AppendChild($selector.CloneNode($true))
                    ReadFileDeclarations $container
                }
            }
            foreach ($entry in $entries) {
                $rule = $document.CreateElement('Filter')
                $rule.SetAttribute('filter', $folder)
                if ($filter.HasAttribute('preserveTree')) {
                    $rule.SetAttribute('preserveTree', $filter.GetAttribute('preserveTree'))
                }
                if ($solution) { $rule.SetAttribute('scope', 'solution') }
                $isOutput = $entry.Name -cin @('Output', 'Generated')
                $field = if ($solution -and $isOutput) { 'generatedPath' } else { 'path' }
                $rule.SetAttribute($field, $entry.InnerText.Trim())
                if ($solution -and $entry.Name -cin @('Header', 'Source')) { $rule.SetAttribute('selection', $entry.Name) }
                if (-not $solution -and $isOutput) { $rule.SetAttribute('planned', 'true') }
                if ($selector.Name -ceq 'Match') { $rule.SetAttribute('match', $value) }
                [void]$filters.InsertBefore($rule, $filter)
            }
        }
        [void]$filters.RemoveChild($filter)
    }
}

function ConvertFrom-UdkManifestXml([System.Xml.XmlElement]$Root) {
    if ($Root.LocalName -ceq 'Component') {
        $Root = $Root.CloneNode($true)
        Convert-UdkComponentFiles $Root
        foreach ($project in $Root.SelectNodes('Projects/Project')) {
            Convert-UdkComponentFiles $project
        }
    }
    $listItems = @{
        Headers = 'Header'; ExcludeHeaders = 'Header'; Sources = 'Source'; ExcludeSources = 'Source'
        Filters = 'Filter'; Dependencies = 'Dependency'; RuntimeDependencies = 'Dependency'
        SupportedPlatforms = 'Platform'; IncludeDirectories = 'IncludeDirectory'
        PreprocessorDefinitions = 'PreprocessorDefinition'; LinkLibraries = 'Library'
        ProjectNames = 'ProjectNameRule'; Contents = 'Content'; ReleaseDependencies = 'ReleaseDependency'
        Mappings = 'Mapping'; Include = 'Path'; Exclude = 'Path'; When = 'Delivery'
        Abis = 'Abi'; Tasks = 'Task'; Configurations = 'Configuration'; NoWarn = 'Warning'
        SupportedRuntimes = 'Runtime'; Components = 'Component'; Includes = 'Include'; Excludes = 'Exclude'
        Platforms = 'Platform'; NativeProps = 'Prop'
        ProjectDirectory = 'ProjectDirectoryRule'; SolutionFolder = 'SolutionFolderRule'
        Variant = 'Variant'; Variants = 'Variant'; MSBuildApplications = 'Application'
        SourceSettings = 'SourceSetting'; Files = 'File'; BrowseFiles = 'File'; PublicHeaders = 'Header'
        Props = 'Prop'; Targets = 'Target'; DynamicDefinitions = 'Definition'
    }
    $legacyRuleNames = @{
        ProjectNames = 'ProjectName'; ProjectDirectory = 'Rule'; SolutionFolder = 'Rule'
    }
    $compactLists = @(
        'Abis', 'Configurations', 'Deliveries', 'DynamicDefinitions', 'LinkLibraries', 'NoWarn', 'Platforms',
        'PreprocessorDefinitions', 'SupportedPlatforms', 'SupportedRuntimes', 'Tasks', 'Variants', 'When'
    )
    function SplitList([string]$Value, [string]$Field, [char]$Separator = ';') {
        foreach ($valueItem in $Value.Split($Separator)) {
            $item = $valueItem.Trim()
            if (-not $item) {
                throw "Empty item in $Field."
            }
            $item
        }
    }
    function ConvertValue([string]$Name, [string]$Value) {
        if ($Name -cin @('schemaVersion', 'cxxStandard', 'apiLevel', 'parallel', 'abiVersion') -and $Value -cmatch '^[0-9]+$') {
            return [long]$Value
        }
        if ($Name -cin @('preserveTree', 'planned', 'threads', 'AllowUnsafeBlocks', 'preserveHierarchy', 'refreshDependencies', 'noDefaultExcludes', 'selfContained')) {
            if ($Value -ceq 'true') {
                return $true
            }
            if ($Value -ceq 'false') {
                return $false
            }
            throw "Invalid XML boolean for ${Name}: $Value"
        }
        return $Value
    }
    function ReadElement([System.Xml.XmlElement]$Element, [string]$Field) {
        $children = @($Element.SelectNodes('*'))
        $value = (@($Element.SelectNodes('text()') | ForEach-Object Value) -join '').Trim()
        if ($Element.NamespaceURI -or ($value -and ($children.Count -or $Element.Attributes.Count))) {
            throw "Unexpected namespace or mixed XML content in $($Element.LocalName)"
        }
        $itemName = $listItems[$Element.LocalName]
        if ($Element.LocalName -ceq 'ProjectName' -and $Field -ceq 'projectNames') {
            $itemName = 'ProjectNameRule'
        }
        if (($Element.LocalName -ceq 'Include' -and $Element.ParentNode.LocalName -ceq 'Includes') -or
            ($Element.LocalName -ceq 'Exclude' -and $Element.ParentNode.LocalName -ceq 'Excludes')) {
            $itemName = $null
        }
        if ($Element.LocalName -ceq 'Projects') {
            if ($Root.LocalName -ceq 'Package' -and $Element.ParentNode -eq $Root) {
                if ($value -and -not $children.Count) {
                    return $value
                }
                return ,(ReadMap $Element 'Project' 'id')
            }
            if ($Root.LocalName -ceq 'Component') {
                $itemName = 'Project'
            }
        }
        if ($Element.LocalName -ceq 'Deliveries') {
            if ($Element.ParentNode -eq $Root -and $Root.LocalName -ceq 'Package') {
                return ,(ReadMap $Element 'Delivery' 'name')
            }
            $itemName = 'Delivery'
        }
        if ($Element.LocalName -ceq 'Rename') {
            return ,(ReadMap $Element 'File' 'from')
        }
        if ($Element.LocalName -ceq 'When' -and $Element.ParentNode.LocalName -cne 'ReleaseDependency') {
            $itemName = $null
        }
        if ($Element.LocalName -cin @('ProjectDirectory', 'SolutionFolder', 'Variant') -and -not $children.Count -and $value) {
            $itemName = $null
        }
        if ($Element.LocalName -cin @('Props', 'Targets') -and -not $children.Count -and $value) {
            $itemName = $null
        }
        if ($Element.ParentNode.LocalName -ceq 'PlatformSources') {
            $itemName = 'Source'
        }
        if ($Element.LocalName -ceq 'Properties' -and $Element.ParentNode.LocalName -ceq 'Preparation') {
            $itemName = 'Property'
        }
        if ($itemName) {
            if ($Element.Attributes.Count) {
                throw "Unexpected attributes in XML list $($Element.LocalName)"
            }
            if ($Element.ParentNode.LocalName -ceq 'MSBuild' -and
                $Element.LocalName -cin @('ProjectName', 'ProjectDirectory', 'SolutionFolder') -and
                $Element.SelectSingleNode('When | Default')) {
                return ,@(for ($index = 0; $index -lt $children.Count; $index++) {
                    $branch = $children[$index]
                    $template = $branch.InnerText.Trim()
                    if ($branch.NamespaceURI -or $branch.SelectSingleNode('*') -or -not $template) {
                        throw "Expected a text template in $($Element.LocalName)/$($branch.LocalName)."
                    }
                    if ($branch.LocalName -ceq 'Default') {
                        if ($branch.Attributes.Count -or $index -ne $children.Count - 1) {
                            throw "Default must be last and have no attributes in $($Element.LocalName)."
                        }
                        [pscustomobject]@{ template = $template }
                        continue
                    }
                    if ($branch.LocalName -cne 'When' -or -not $branch.Attributes.Count) {
                        throw "Expected When with condition attributes in $($Element.LocalName)."
                    }
                    $conditions = [ordered]@{}
                    foreach ($attribute in $branch.Attributes) {
                        if ($attribute.NamespaceURI) {
                            throw "Unexpected XML attribute: $($attribute.Name)"
                        }
                        $conditions[$attribute.Name] = @(SplitList $attribute.Value "$($Element.LocalName)/When.$($attribute.Name)")
                    }
                    [pscustomobject]@{ when = [pscustomobject]$conditions; template = $template }
                })
            }
            if ($value) {
                if ($Element.LocalName -cnotin $compactLists) {
                    throw "Expected nested elements in $($Element.LocalName)"
                }
                return ,@(SplitList $value $Element.LocalName)
            }
            return ,@(foreach ($child in $children) {
                if ($child.LocalName -cne $itemName -and $child.LocalName -cne $legacyRuleNames[$Element.LocalName]) {
                    throw "Expected $itemName in $($Element.LocalName)."
                }
                if ($Element.LocalName -ceq 'Filters' -and $child.SelectSingleNode('Generated')) {
                    if ($child.GetAttribute('scope') -cne 'solution' -or $child.HasAttribute('path') -or
                        $child.SelectSingleNode('text()[normalize-space()]')) {
                        throw 'Generated selectors require a solution Filter with nested selectors.'
                    }
                    foreach ($selector in $child.SelectNodes('*')) {
                        $rule = $child.CloneNode($false)
                        if ($selector.Name -ceq 'Generated' -and -not $selector.Attributes.Count -and
                            -not $selector.SelectSingleNode('*') -and $selector.InnerText.Trim()) {
                            $rule.SetAttribute('generatedPath', $selector.InnerText.Trim())
                        } elseif ($selector.Name -ceq 'Path' -and -not $selector.Attributes.Count -and
                            -not $selector.SelectSingleNode('*') -and $selector.InnerText.Trim()) {
                            $rule.SetAttribute('path', $selector.InnerText.Trim())
                        } else {
                            throw 'Expected a nonempty Path or Generated element in solution Filter.'
                        }
                        ReadElement $rule $Field
                    }
                    continue
                }
                if ($Element.LocalName -ceq 'Filters' -and $child.SelectSingleNode('Path') -and
                    ($child.HasAttribute('filter') -or $child.SelectNodes('Path').Count -gt 1)) {
                    if ($child.HasAttribute('path') -or $child.SelectSingleNode('text()[normalize-space()]')) {
                        throw 'Use either the path attribute or nested Path elements in Filter.'
                    }
                    $rule = $child.CloneNode($false)
                    foreach ($path in $child.SelectNodes('*')) {
                        $pattern = $path.InnerText.Trim()
                        if ($path.Name -cne 'Path' -or $path.NamespaceURI -or $path.Attributes.Count -or
                            $path.SelectSingleNode('*') -or -not $pattern) {
                            throw 'Expected a nonempty Path element in Filter.'
                        }
                        $rule.SetAttribute('path', $pattern)
                        ReadElement $rule $Field
                    }
                    continue
                }
                ReadElement $child $Field
            })
        }
        if (-not $children.Count -and -not $Element.Attributes.Count -and $Element -ne $Root -and
            $Element.LocalName -cnotin @('Variables', 'Properties', 'Parameters', 'BuildExtensions', 'Requirements')) {
            return (ConvertValue $Field $value)
        }
        $fields = [ordered]@{}
        foreach ($attribute in $Element.Attributes) {
            if ($attribute.NamespaceURI) {
                throw "Unexpected XML attribute: $($attribute.Name)"
            }
            if ($Element.LocalName -ceq 'When' -and $attribute.Name -ceq 'variant' -and $attribute.Value -match '[;,]') {
                $separator = if ($attribute.Value.Contains(';')) {
                    ';'
                } else {
                    ','
                }
                $fields['variant'] = @(SplitList $attribute.Value 'When.variant' $separator)
            } else {
                $fields[$attribute.Name] = ConvertValue $attribute.Name $attribute.Value
            }
        }
        foreach ($child in $children) {
            $name = $child.LocalName
            if ($Element.LocalName -ceq 'MSBuild' -and $name -ceq 'ProjectName' -and $child.SelectSingleNode('*')) {
                $name = 'ProjectNames'
            }
            if ($Root.LocalName -ceq 'Package' -and $Element.LocalName -ceq 'Content') {
                if ($name -ceq 'Includes') {
                    $name = 'Include'
                }
                if ($name -ceq 'Excludes') {
                    $name = 'Exclude'
                }
            }
            if ($Element.LocalName -cnotin @('Properties', 'PlatformRequirements', 'PlatformSources', 'Variables', 'Parameters')) {
                $name = switch -CaseSensitive ($name) {
                    'MSBuild' {
                        'msbuild'
                    }
                    'MSBuildProps' {
                        'msbuildProps'
                    }
                    'MSBuildTargets' {
                        'msbuildTargets'
                    }
                    'CMake' {
                        'cmake'
                    }
                    default {
                        $name.Substring(0, 1).ToLowerInvariant() + $name.Substring(1)
                    }
                }
            }
            if ($fields.Contains($name)) {
                throw "Duplicate XML field '$name' in $($Element.LocalName)"
            }
            $fields[$name] = ReadElement $child $name
        }
        return [pscustomobject]$fields
    }
    function ReadMap([System.Xml.XmlElement]$Element, [string]$ItemName, [string]$KeyAttribute) {
        if ($Element.Attributes.Count -or $Element.SelectNodes('text()[normalize-space()]').Count) {
            throw "Expected nested entries in $($Element.LocalName)"
        }
        $map = [ordered]@{}
        foreach ($child in $Element.SelectNodes('*')) {
            $key = $child.GetAttribute($KeyAttribute)
            if ($child.LocalName -cne $ItemName -or -not $key -or $map.Contains($key)) {
                throw "Invalid or duplicate entry in $($Element.LocalName): $key"
            }
            $child = $child.CloneNode($true)
            $child.RemoveAttribute($KeyAttribute)
            $map[$key] = ReadElement $child ''
        }
        return [pscustomobject]$map
    }
    ReadElement $Root ''
}

function Read-UdkManifestDocument([string]$File) {
    $settings = [System.Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $reader = [System.Xml.XmlReader]::Create($file, $settings)
    $document = [System.Xml.XmlDocument]::new()
    try {
        $document.Load($reader)
    } finally {
        $reader.Dispose()
    }
    return ,$document
}

function Convert-UdkManifestShorthand([System.Xml.XmlElement]$Root) {
    $document = $Root.OwnerDocument
    foreach ($settings in @($Root.SelectNodes('Generation/Settings'))) {
        if ($Root.Name -cne 'ComponentRegistry' -or $settings.GetAttribute('buildSystem') -cne 'MSBuild' -or
            $settings.Attributes.Count -ne 1 -or $settings.ParentNode.SelectSingleNode('MSBuild')) {
            throw 'Expected one Generation Settings block for MSBuild.'
        }
        $msbuild = $document.CreateElement('MSBuild')
        while ($settings.HasChildNodes) { [void]$msbuild.AppendChild($settings.FirstChild) }
        [void]$settings.ParentNode.ReplaceChild($msbuild, $settings)
    }
    foreach ($extension in $Root.SelectNodes('.//Extension[@buildSystem]')) {
        if ($extension.HasAttribute('backend')) { throw 'Specify only buildSystem on Extension.' }
        $extension.SetAttribute('backend', $extension.GetAttribute('buildSystem'))
        $extension.RemoveAttribute('buildSystem')
    }
    foreach ($owner in @($Root) + @($Root.SelectNodes('Projects/Project|Extension|Projects/Project/Extension|Projects/Project/Extension/ConsumerIntegration'))) {
        $inputs = @($owner.SelectNodes('Files.Input'))
        if (-not $inputs.Count) { continue }
        if ($owner.SelectSingleNode('Files')) { throw 'Use either Files or Files.Input in the same block.' }
        $files = $document.CreateElement('Files')
        [void]$owner.InsertBefore($files, $inputs[0])
        foreach ($entry in $inputs) {
            $inputFile = $document.CreateElement('Input')
            foreach ($attribute in $entry.Attributes) { [void]$inputFile.Attributes.Append($attribute.CloneNode($true)) }
            while ($entry.HasChildNodes) { [void]$inputFile.AppendChild($entry.FirstChild) }
            [void]$files.AppendChild($inputFile)
            [void]$owner.RemoveChild($entry)
        }
    }
    foreach ($project in $Root.SelectNodes('Projects/Project')) {
        foreach ($extension in $project.SelectNodes('Extension')) {
            $blocks = @($extension.SelectNodes('ConsumerIntegration|ConsumerIntegration.Files|ConsumerIntegration.Files.Input'))
            if (-not $blocks.Count) { continue }
            if ($blocks.Count -ne 1 -or ($blocks[0].Name -cne 'ConsumerIntegration.Files.Input' -and $blocks[0].Attributes.Count)) {
                throw 'Expected one ConsumerIntegration declaration per build system.'
            }
            $block = $blocks[0]
            $files = if ($block.Name -ceq 'ConsumerIntegration') { $block.SelectSingleNode('Files') } else { $block }
            if (-not $files -or ($block.Name -ceq 'ConsumerIntegration' -and
                ($block.SelectNodes('*').Count -ne 1 -or $block.SelectSingleNode('text()[normalize-space()]'))) -or
                ($block.Name -cne 'ConsumerIntegration.Files.Input' -and
                ($files.Attributes.Count -or $files.SelectNodes('*').Count -ne 1 -or $files.SelectSingleNode('text()[normalize-space()]')))) {
                throw 'Expected one Files input in ConsumerIntegration.'
            }
            $inputFile = if ($block.Name -ceq 'ConsumerIntegration.Files.Input') { $block } else { $files.SelectSingleNode('Input') }
            $system, $role, $attribute = switch -CaseSensitive ($extension.GetAttribute('backend')) {
                'MSBuild' { 'MSBuild', 'msbuild-props', 'props' }
                'CMake' { 'CMake', 'cmake', 'script' }
                default { throw 'Unsupported ConsumerIntegration build system.' }
            }
            if (-not $inputFile -or $inputFile.Attributes.Count -ne 1 -or $inputFile.GetAttribute('role') -cne $role -or
                $inputFile.SelectSingleNode('*') -or -not $inputFile.InnerText.Trim()) {
                throw "Expected one ConsumerIntegration input with role '$role'."
            }
            $integration = $project.SelectSingleNode('ConsumerIntegration')
            if (-not $integration) {
                $integration = $document.CreateElement('ConsumerIntegration')
                [void]$project.InsertBefore($integration, $extension)
            }
            if ($integration.SelectSingleNode($system)) { throw "Duplicate ConsumerIntegration for $system." }
            $entry = $document.CreateElement($system)
            $entry.SetAttribute($attribute, $inputFile.InnerText.Trim())
            [void]$integration.AppendChild($entry)
            [void]$extension.RemoveChild($block)
        }
    }
}

function Resolve-UdkNativeDependencyTargets([System.Xml.XmlElement]$Root, $RegistryScope) {
    $dependencies = @($Root.SelectNodes('Projects/Project[@kind="library" and @projectType="native"]/Dependencies/Dependency[@target]'))
    if (-not $dependencies.Count) { return }
    if (-not $RegistryScope -or -not $RegistryScope.RegistryRoot) { throw 'Native dependency targets require a component registry.' }
    if ($null -eq $RegistryScope.NativeTargets) {
        $targets = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
        foreach ($relative in $RegistryScope.ComponentPaths) {
            if ($relative -isnot [string] -or $relative -match '[\\:$@%*?;\r\n]' -or
                @($relative.Split('/') | Where-Object { $_ -in @('', '.', '..') }).Count) {
                throw "Invalid registry component path: $relative"
            }
            $manifestPath = Resolve-UdkManifestPath (Join-Path $RegistryScope.RegistryRoot $relative)
            $definition = (Read-UdkManifestDocument $manifestPath).DocumentElement
            foreach ($project in $definition.SelectNodes('Projects/Project[@kind="library" and @projectType="native" and @target]')) {
                $target = $project.GetAttribute('target')
                if ($targets.ContainsKey($target)) { throw "Duplicate native target: $target" }
                $targets.Add($target, $definition.GetAttribute('name'))
            }
        }
        $RegistryScope.NativeTargets = $targets
    }
    foreach ($dependency in $dependencies) {
        $target = $dependency.GetAttribute('target')
        if ($dependency.HasAttribute('component') -or -not $RegistryScope.NativeTargets.ContainsKey($target)) {
            throw "Invalid native dependency target: $target"
        }
        $dependency.RemoveAttribute('target')
        $dependency.SetAttribute('component', $RegistryScope.NativeTargets[$target])
    }
}

function Read-UdkManifest([string]$Path, [string]$XmlRoot, $RegistryScope) {
    $file = Resolve-UdkManifestPath $Path
    $document = Read-UdkManifestDocument $file
    if ($document.DocumentElement.LocalName -cne $XmlRoot) {
        throw "Expected <$XmlRoot> in $file"
    }
    $root = $document.DocumentElement
    if ($XmlRoot -cin @('ComponentRegistry', 'Component')) { Convert-UdkManifestShorthand $root }
    if ($XmlRoot -ceq 'ComponentRegistry' -and $root.GetAttribute('schemaVersion') -cin @('7', '8')) {
        $scope = Convert-UdkFileScope $root $null
        Convert-UdkComponentFiles $root
        $registry = ConvertFrom-UdkManifestXml $root
        $scope | Add-Member RegistryRoot (Split-Path -Parent $file)
        $scope | Add-Member ComponentPaths @($registry.components)
        $scope | Add-Member NativeTargets $null
        $msbuild = $registry.generation.msbuild
        if ($msbuild.solutionName -cnotmatch '^[A-Za-z0-9_.-]+$' -or $msbuild.solutionName -in @('.', '..') -or $msbuild.solution) {
            throw 'Expected SolutionName in the registry.'
        }
        $msbuild | Add-Member solution ($msbuild.solutionName + '.sln')
        $versionInputs = @($scope.Inputs | Where-Object { $_.GetAttribute('role') -ceq 'version-source' })
        if ($versionInputs.Count -ne 1 -or $versionInputs[0].InnerText.Trim() -match '[*?]') {
            throw 'Expected one version-source input with a literal path.'
        }
        $integration = @{ versionSource = $versionInputs[0].InnerText.Trim() }
        foreach ($entry in @{
            sourcesTargets = 'sourceIntegration-targets'; coreExportHeader = 'core-exportHeader'
            versionHeader = 'version-header'; versionProps = 'version-props'
        }.GetEnumerator()) {
            $template = $scope.Outputs[$entry.Value]
            if (-not $template) { throw "Missing output template: $($entry.Value)" }
            $value = $template.Replace('{solutionName}', $msbuild.solutionName).Replace('{ext}', (Get-UdkOutputExtension $entry.Value))
            if ($value -match '[{}]') { throw "Invalid registry output template: $template" }
            $integration[$entry.Key] = $value
        }
        $registry.generation | Add-Member integration ([pscustomobject]$integration)
        $registry | Add-Member fileScope $scope
        return $registry
    }
    if ($XmlRoot -ceq 'Component') {
        $newFiles = $root.SelectSingleNode('.//Files//Input|.//Files//Output|.//Files//Group[@id]|.//Ref|.//Extension')
        if ($newFiles -or $RegistryScope -or $root.SelectSingleNode('Projects/Project/Dependencies/Dependency[@target]')) {
            if (-not $RegistryScope) {
                $directory = [IO.DirectoryInfo]::new((Split-Path -Parent $file))
                while ($directory) {
                    $candidate = Join-Path $directory.FullName 'Components.xml'
                    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                        $RegistryScope = (Read-UdkManifest $candidate 'ComponentRegistry').fileScope
                        break
                    }
                    $directory = $directory.Parent
                }
            }
            Resolve-UdkNativeDependencyTargets $root $RegistryScope
            $scope = Convert-UdkFileScope $root $RegistryScope
            $projectScopes = @(foreach ($project in $root.SelectNodes('Projects/Project')) {
                Convert-UdkFileScope $project $scope
            })
            $component = ConvertFrom-UdkManifestXml $root
            for ($index = 0; $index -lt $projectScopes.Count; $index++) {
                $component.projects[$index] | Add-Member outputScope $projectScopes[$index]
            }
            return $component
        }
    }
    ConvertFrom-UdkManifestXml $root
}