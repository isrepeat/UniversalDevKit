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

function ConvertFrom-UdkManifestXml([System.Xml.XmlElement]$Root) {
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
        SourceSettings = 'SourceSetting'; Files = 'File'; PublicHeaders = 'Header'
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
        if ($Name -cin @('preserveTree', 'threads', 'AllowUnsafeBlocks', 'preserveHierarchy', 'refreshDependencies', 'noDefaultExcludes', 'selfContained')) {
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

function Read-UdkManifest([string]$Path, [string]$XmlRoot) {
    $file = Resolve-UdkManifestPath $Path
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
    if ($document.DocumentElement.LocalName -cne $XmlRoot) {
        throw "Expected <$XmlRoot> in $file"
    }
    ConvertFrom-UdkManifestXml $document.DocumentElement
}