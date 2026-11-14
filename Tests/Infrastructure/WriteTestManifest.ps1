. (Join-Path $PSScriptRoot '../../Sources/Windows/UdkCli/Tools/ReadManifest.ps1')

function Get-TestManifestRoot([string]$Name) {
    switch ([IO.Path]::GetFileNameWithoutExtension($Name)) {
        'Package' { 'Package' }
        { $_ -in @('Delivery', 'Maven') } { 'Delivery' }
        { $_ -in @('Projects', 'Registry') } { 'BuildProjectRegistry' }
        default { 'Project' }
    }
}

function ConvertTo-TestManifestXml($Value, [string]$Root) {
    $document = [xml]::new()
    $items = @{
        components='Component'; includes='Include'; projects='Project'; headers='Header'; excludeHeaders='Header'
        sources='Source'; excludeSources='Source'; filters='Filter'; dependencies='Dependency'
        runtimeDependencies='Dependency'; supportedPlatforms='Platform'; includeDirectories='IncludeDirectory'
        preprocessorDefinitions='PreprocessorDefinition'; linkLibraries='Library'
        contents='Content'; releaseDependencies='ReleaseDependency'; mappings='Mapping'; include='Include'
        exclude='Exclude'; when='Delivery'; abis='Abi'; tasks='Task'; configurations='Configuration'
        noWarn='Warning'; supportedRuntimes='Runtime'; platforms='Platform'; nativeProps='Prop'
        props='Prop'; targets='Target'; variant='Variant'
        variants='Variant'; msbuildApplications='Application'; sourceSettings='SourceSetting'; files='File'
        publicHeaders='Header'; dynamicDefinitions='Definition'; deliveries='Delivery'; properties='Property'
    }
    function AddElement($Parent, [string]$Name, $Data, [string]$Field) {
        $element = $document.CreateElement($Name)
        [void]$Parent.AppendChild($element)
        if ($Name -ceq 'Filter' -and $Parent.LocalName -ceq 'Filters') {
            $element.SetAttribute('filter', $Data.filter)
            if ($null -ne $Data.preserveTree) {
                $element.SetAttribute('preserveTree', $Data.preserveTree.ToString().ToLowerInvariant())
            }
            AddElement $element 'Path' $Data.path ''
            return
        }
        if ($Data -is [array]) {
            if ($Field -in @('projectNames', 'projectDirectory', 'solutionFolder')) {
                foreach ($rule in $Data) {
                    if ($rule.when) {
                        AddElement $element 'When' $rule.template ''
                        foreach ($condition in $rule.when.GetEnumerator()) {
                            $element.LastChild.SetAttribute($condition.Key, ($condition.Value -join ';'))
                        }
                    } else {
                        AddElement $element 'Default' $rule.template ''
                    }
                }
                return
            }
            $item = $items[$Field]
            if ($Parent.LocalName -eq 'PlatformSources') { $item = 'Source' }
            if (-not $item) { $item = 'Item' }
            foreach ($entry in $Data) { AddElement $element $item $entry '' }
        } elseif ($Data -is [System.Collections.IDictionary] -or $Data -is [pscustomobject]) {
            $entries = if ($Data -is [System.Collections.IDictionary]) {
                $Data.GetEnumerator() | ForEach-Object { @{ Name = $_.Key; Value = $_.Value } }
            } else {
                $Data.PSObject.Properties
            }
            :fields foreach ($entry in $entries) {
                $key = $entry.Name
                switch ($Name) {
                    'Projects' {
                        if ($Parent.LocalName -eq 'Package') {
                            AddElement $element 'Project' $entry.Value ''
                            $element.LastChild.SetAttribute('id', $key)
                            continue fields
                        }
                    }
                    'Deliveries' {
                        AddElement $element 'Delivery' $entry.Value ''
                        $element.LastChild.SetAttribute('name', $key)
                        continue fields
                    }
                    'Rename' {
                        AddElement $element 'File' $entry.Value ''
                        $element.LastChild.SetAttribute('from', $key)
                        continue fields
                    }
                }
                $tag = switch -CaseSensitive ($key) {
                    'msbuild' { 'MSBuild' }
                    'projectNames' { 'ProjectName' }
                    'msbuildProps' { 'MSBuildProps' }
                    'msbuildTargets' { 'MSBuildTargets' }
                    'cmake' { 'CMake' }
                    'include' { 'Includes' }
                    'exclude' { 'Excludes' }
                    default { $key.Substring(0, 1).ToUpperInvariant() + $key.Substring(1) }
                }
                AddElement $element $tag $entry.Value $key
            }
        } elseif ($null -ne $Data) {
            $element.InnerText = if ($Data -is [bool]) { $Data.ToString().ToLowerInvariant() } else { [string]$Data }
        }
    }
    AddElement $document $Root $Value ''
    $document.OuterXml
}