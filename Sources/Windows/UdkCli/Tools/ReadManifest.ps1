function Resolve-UdkManifestPath([string]$Path) {
    $extension = [IO.Path]::GetExtension($Path)
    $candidates = if ($extension -in @('.json', '.xml')) { $Path } else { "$Path.json"; "$Path.xml" }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    throw "Missing manifest: $Path"
}

function Get-UdkPackageManifests([string]$Root) {
    Get-ChildItem -LiteralPath $Root -Recurse -File -Filter 'Package.*' |
        Where-Object Extension -in @('.json', '.xml') |
        Group-Object DirectoryName |
        Sort-Object Name |
        ForEach-Object { Get-Item -LiteralPath (Resolve-UdkManifestPath (Join-Path $_.Name 'Package')) }
}

function ConvertFrom-UdkManifestXml([System.Xml.XmlElement]$Root) {
    $listItems = @{
        Headers = 'Header'; ExcludeHeaders = 'Header'; Sources = 'Source'; ExcludeSources = 'Source'
        Filters = 'Filter'; Dependencies = 'Dependency'; RuntimeDependencies = 'Dependency'
        SupportedPlatforms = 'Platform'; IncludeDirectories = 'IncludeDirectory'
        PreprocessorDefinitions = 'PreprocessorDefinition'; LinkLibraries = 'Library'
        ProjectNames = 'ProjectName'; Contents = 'Content'; ReleaseDependencies = 'ReleaseDependency'
        Mappings = 'Mapping'; Include = 'Path'; Exclude = 'Path'; When = 'Delivery'
        Abis = 'Abi'; Tasks = 'Task'; Configurations = 'Configuration'; NoWarn = 'Warning'
        SupportedRuntimes = 'Runtime'; Components = 'Component'; Includes = 'Include'; Excludes = 'Exclude'
        Platforms = 'Platform'; NativeProps = 'Prop'; ProjectDirectory = 'Rule'; SolutionFolder = 'Rule'
        Variant = 'Variant'; Variants = 'Variant'; MSBuildApplications = 'Application'
        SourceSettings = 'SourceSetting'; Files = 'File'; PublicHeaders = 'Header'
        Props = 'Prop'; Targets = 'Target'
    }
    $compactLists = @(
        'Abis', 'Configurations', 'Deliveries', 'LinkLibraries', 'NoWarn', 'Platforms',
        'PreprocessorDefinitions', 'SupportedPlatforms', 'SupportedRuntimes', 'Tasks', 'Variants', 'When'
    )
    function SplitList([string]$Value, [string]$Field, [char]$Separator = ';') {
        foreach ($valueItem in $Value.Split($Separator)) {
            $item = $valueItem.Trim()
            if (-not $item) { throw "Empty item in $Field." }
            $item
        }
    }
    function ConvertValue([string]$Name, [string]$Value) {
        if ($Name -cin @('schemaVersion', 'cxxStandard', 'apiLevel', 'parallel', 'abiVersion') -and $Value -cmatch '^[0-9]+$') {
            return [long]$Value
        }
        if ($Name -cin @('preserveTree', 'threads', 'AllowUnsafeBlocks', 'preserveHierarchy', 'refreshDependencies', 'noDefaultExcludes')) {
            if ($Value -ceq 'true') { return $true }
            if ($Value -ceq 'false') { return $false }
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
        if (($Element.LocalName -ceq 'Include' -and $Element.ParentNode.LocalName -ceq 'Includes') -or
            ($Element.LocalName -ceq 'Exclude' -and $Element.ParentNode.LocalName -ceq 'Excludes')) {
            $itemName = $null
        }
        if ($Element.LocalName -ceq 'Projects') {
            if ($Root.LocalName -ceq 'Package' -and $Element.ParentNode -eq $Root) {
                if ($value -and -not $children.Count) { return $value }
                return ,(ReadMap $Element 'Project' 'id')
            }
            if ($Root.LocalName -ceq 'Component') { $itemName = 'Project' }
        }
        if ($Element.LocalName -ceq 'Deliveries') {
            if ($Element.ParentNode -eq $Root -and $Root.LocalName -ceq 'Package') {
                return ,(ReadMap $Element 'Delivery' 'name')
            }
            $itemName = 'Delivery'
        }
        if ($Element.LocalName -ceq 'Rename') { return ,(ReadMap $Element 'File' 'from') }
        if ($Element.LocalName -ceq 'When' -and $Element.ParentNode.LocalName -cne 'ReleaseDependency') { $itemName = $null }
        if ($Element.LocalName -cin @('ProjectDirectory', 'SolutionFolder', 'Variant') -and -not $children.Count -and $value) { $itemName = $null }
        if ($Element.LocalName -cin @('Props', 'Targets') -and -not $children.Count -and $value) { $itemName = $null }
        if ($Element.ParentNode.LocalName -ceq 'PlatformSources') { $itemName = 'Source' }
        if ($Element.LocalName -ceq 'Properties' -and $Element.ParentNode.LocalName -ceq 'Preparation') { $itemName = 'Property' }
        if ($itemName) {
            if ($Element.Attributes.Count) { throw "Unexpected attributes in XML list $($Element.LocalName)" }
            if ($value) {
                if ($Element.LocalName -cnotin $compactLists) {
                    throw "Expected nested elements in $($Element.LocalName)"
                }
                return ,@(SplitList $value $Element.LocalName)
            }
            return ,@(foreach ($child in $children) {
                if ($child.LocalName -cne $itemName) { throw "Expected $itemName in $($Element.LocalName)." }
                ReadElement $child $Field
            })
        }
        if (-not $children.Count -and -not $Element.Attributes.Count -and $Element -ne $Root -and
            $Element.LocalName -cnotin @('Variables', 'Properties', 'Parameters', 'BuildExtensions', 'Requirements')) {
            return (ConvertValue $Field $value)
        }
        $fields = [ordered]@{}
        foreach ($attribute in $Element.Attributes) {
            if ($attribute.NamespaceURI) { throw "Unexpected XML attribute: $($attribute.Name)" }
            if ($Element.LocalName -ceq 'When' -and $attribute.Name -ceq 'variant' -and $attribute.Value -match '[;,]') {
                $separator = if ($attribute.Value.Contains(';')) { ';' } else { ',' }
                $fields['variant'] = @(SplitList $attribute.Value 'When.variant' $separator)
            } else {
                $fields[$attribute.Name] = ConvertValue $attribute.Name $attribute.Value
            }
        }
        foreach ($child in $children) {
            $name = $child.LocalName
            if ($Root.LocalName -ceq 'Package' -and $Element.LocalName -ceq 'Content') {
                if ($name -ceq 'Includes') { $name = 'Include' }
                if ($name -ceq 'Excludes') { $name = 'Exclude' }
            }
            if ($Element.LocalName -cnotin @('Properties', 'PlatformRequirements', 'PlatformSources', 'Variables', 'Parameters')) {
                $name = switch -CaseSensitive ($name) {
                    'MSBuild' { 'msbuild' }
                    'MSBuildProps' { 'msbuildProps' }
                    'MSBuildTargets' { 'msbuildTargets' }
                    'CMake' { 'cmake' }
                    default { $name.Substring(0, 1).ToLowerInvariant() + $name.Substring(1) }
                }
            }
            if ($fields.Contains($name)) { throw "Duplicate XML field '$name' in $($Element.LocalName)" }
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
    switch ([IO.Path]::GetExtension($file)) {
        '.json' { return (Get-Content -LiteralPath $file -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json) }
        '.xml' {
            $settings = [System.Xml.XmlReaderSettings]::new()
            $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
            $settings.XmlResolver = $null
            $reader = [System.Xml.XmlReader]::Create($file, $settings)
            $document = [System.Xml.XmlDocument]::new()
            try { $document.Load($reader) } finally { $reader.Dispose() }
            if ($document.DocumentElement.LocalName -cne $XmlRoot) { throw "Expected <$XmlRoot> in $file" }
            return (ConvertFrom-UdkManifestXml $document.DocumentElement)
        }
        default { throw "Unsupported manifest format: $file" }
    }
}