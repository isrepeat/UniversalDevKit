function ConvertTo-ProjectToolsXml([string]$Value) {
    return [Security.SecurityElement]::Escape($Value)
}

function Get-ProjectToolsApplicationProperties($Component, [string[]]$Reserved) {
    foreach ($property in $Component.msbuild.properties.PSObject.Properties) {
        if ($property.Name -notmatch '^[A-Za-z_][A-Za-z0-9_]*$' -or $property.Name -in $Reserved) {
            throw "Invalid application MSBuild property: $($property.Name)"
        }
        '    <' + $property.Name + '>' + (ConvertTo-ProjectToolsXml $property.Value) + '</' + $property.Name + '>'
    }
}

function Get-ProjectToolsTemplateValues($Component, [string]$Variant) {
    $artifact = switch ($Variant) {
        'Shared' {
            'sharedItems'
        }
        'Dependencies' {
            'dependencies'
        }
        'HeaderCheck' {
            'headerCheck'
        }
        default {
            'project'
        }
    }
    $kind = if ($Component.kind -eq 'application') {
        'application'
    } else {
        'library'
    }
    $values = @{
        name = $Component.name
        kind = $kind
        projectType = $Component.projectType
        artifact = $artifact
        framework = $Component.msbuild.properties.TargetFramework
    }
    if ($Variant -in @('Static', 'Dynamic')) {
        $values.variant = $Variant.ToLowerInvariant()
    }
    return $values
}

function Resolve-ProjectToolsRuleTemplate($Local, $Root, [hashtable]$Values, [string]$Field) {
    foreach ($rule in @($Local) + @($Root)) {
        if (-not $rule) {
            continue
        }
        if ($rule -is [string]) {
            return $rule
        }
        $mismatches = $rule.when.PSObject.Properties | Where-Object {
            $_ -and (-not $Values[$_.Name] -or $Values[$_.Name] -cnotin @($_.Value))
        }
        if (-not $mismatches) {
            return $rule.template
        }
    }
    throw "No $Field rule for '$($Values.name)' ($($Values.artifact))."
}

function Get-ProjectToolsLayout($Model, $Component, [string]$Variant, [string]$Field) {
    $values = Get-ProjectToolsTemplateValues $Component $Variant
    $local = $Component.msbuild.$Field
    $root = $Model.Settings.$Field
    $template = Resolve-ProjectToolsRuleTemplate $local $root $values $Field
    if (-not $local -and $root -is [string] -and $Model.Settings.projectNames -isnot [array]) {
        $values.kind = $values.kind.Substring(0, 1).ToUpperInvariant() + $values.kind.Substring(1)
    }
    $path = (Expand-ProjectToolsTemplate $template $values).TrimEnd('/')
    Assert-ProjectToolsLayout $path $Field
    return $path
}

function Get-ProjectToolsLocation($Model, $Component, [string]$Variant, [string]$Extension) {
    $directory = Get-ProjectToolsLayout $Model $Component $Variant 'projectDirectory'
    $template = $Model.Settings.projectName
    if ($Model.Settings.projectNames -is [array]) {
        $values = Get-ProjectToolsTemplateValues $Component $Variant
        $template = Resolve-ProjectToolsRuleTemplate $Component.msbuild.projectNames $Model.Settings.projectNames $values 'projectNames'
        $name = Expand-ProjectToolsTemplate $template $values
    } elseif ($Model.Settings.projectNames -or $Component.msbuild.projectNames) {
        $role = if ($Extension -eq '.csproj') {
            'DotNet'
        } else {
            $Variant
        }
        $local = $Component.msbuild.projectNames
        $global = $Model.Settings.projectNames
        $template = @($local.$role, $local.default, $global.$role, $global.default, $template) |
            Where-Object {
                $_
            } | Select-Object -First 1
        if (-not $template) {
            throw "No projectNames template for '$($Component.name)' ($role)."
        }
    } elseif ($Component.msbuild.projectName -and ($Variant -ne 'Shared' -or $Component.kind -ne 'application')) {
        $template = $Component.msbuild.projectName
    } elseif ($Variant -eq 'Shared' -and $Model.Settings.sharedProjectName) {
        $template = $Model.Settings.sharedProjectName
    }
    if ($Model.Settings.projectNames -isnot [array]) {
        $name = $template.Replace('{name}', $Component.name).Replace('{kind}', $Component.kind)
        if ($Variant) {
            $name = $name.Replace('{variant}', $Variant)
        }
        $framework = $Component.msbuild.properties.TargetFramework
        if ($framework) {
            $name = $name.Replace('{framework}', $framework)
        }
    }
    if ($name -cnotmatch '^[A-Za-z0-9_.-]+$' -or $name -in @('.', '..') -or $name.EndsWith('.')) {
        throw "Invalid project name '$name' for '$($Component.name)'. Check the template and available placeholders."
    }
    if (-not $Extension) {
        $Extension = switch ($Variant) {
            'Shared' {
                '.vcxitems'
            }
            'Dependencies' {
                '.props'
            }
            default {
                '.vcxproj'
            }
        }
    }
    $path = $directory + '/' + $name + $extension
    $null = Resolve-ProjectToolsPath $Model.Root $path
    return $path
}

function Get-ProjectToolsNativeProjectTemplate($Model, $Component, [string]$Path) {
    $template = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '../Templates/Component.vcxproj.in'))
    $newline = if ($template.Contains("`r`n")) {
        "`r`n"
    } else {
        "`n"
    }
    $configurations = foreach ($configuration in $Model.Settings.configurations) {
        foreach ($platform in $Model.Settings.platforms) {
            '    <ProjectConfiguration Include="' + $configuration + '|' + $platform + '">'
            '      <Configuration>' + $configuration + '</Configuration>'
            '      <Platform>' + $platform + '</Platform>'
            '    </ProjectConfiguration>'
        }
    }
    $nativeProps = if ($Model.Settings.PSObject.Properties['nativeProps']) {
        $Model.Settings.nativeProps
    } elseif ($Model.Profile -eq 'udk') {
        'Projects/MsBuild/BuildLayout.props'
    }
    $imports = foreach ($file in @($nativeProps) + @($Model.Settings.props) | Where-Object {
        $_
    }) {
        $import = (Get-ProjectToolsRelativeImport $Model $Path $file).Replace('$(MSBuildThisFileDirectory)', '')
        '  <Import Project="' + (ConvertTo-ProjectToolsXml $import) + '" />'
    }
    $shared = Get-ProjectToolsLocation $Model $Component 'Shared'
    $dependencyImport = if ($Model.Integration -or $Model.Profile -eq 'udk') {
        $dependencies = Get-ProjectToolsLocation $Model $Component 'Dependencies'
        '  <Import Project="' + (ConvertTo-ProjectToolsXml (Get-ProjectToolsRelativeFile $Model $Path $dependencies)) + '" />' + $newline
    } else {
        ''
    }
    $globals = foreach ($property in $Component.msbuild.properties.PSObject.Properties) {
        if ($property.Name -notmatch '^[A-Za-z_][A-Za-z0-9_]*$' -or $property.Name -eq 'ProjectGuid') {
            throw 'Invalid MSBuild property.'
        }
        '    <' + $property.Name + '>' + (ConvertTo-ProjectToolsXml $property.Value) + '</' + $property.Name + '>' + $newline
    }
    return $template.Replace('@PROJECT_CONFIGURATIONS@', ($configurations -join $newline)).
        Replace('@NATIVE_PROPS@', ($imports -join $newline)).
        Replace('@SHARED_PROJECT@', (ConvertTo-ProjectToolsXml (Get-ProjectToolsRelativeFile $Model $Path $shared))).
        Replace('@DEPENDENCY_IMPORT@' + $newline, $dependencyImport).
        Replace('@GLOBALS@' + $newline, ($globals -join ''))
}

function Get-ProjectToolsRelativeImport($Model, [string]$ProjectPath, [string]$Target) {
    $directory = Split-Path -Parent (Join-Path $Model.Root $ProjectPath)
    $targetPath = Resolve-ProjectToolsPath $Model.Root $Target
    return '$(MSBuildThisFileDirectory)' + (Get-ProjectToolsRelativePath $directory $targetPath)
}

function Get-ProjectToolsRelativeFile($Model, [string]$From, [string]$To) {
    (Get-ProjectToolsRelativeImport $Model $From $To).Replace('$(MSBuildThisFileDirectory)', '')
}

function Get-ProjectToolsBuildItems($Model, $Component, [string]$SharedPath, [string]$DependenciesPath) {
    $paths = @($Component.buildExtensions.msbuildProps, $Component.buildExtensions.msbuildTargets, $DependenciesPath) |
        Where-Object {
            $_
        } | Select-Object -Unique
    if (-not $paths) {
        return
    }

    '  <ItemGroup>'
    foreach ($file in $paths) {
        $include = ConvertTo-ProjectToolsXml (Get-ProjectToolsRelativeImport $Model $SharedPath $file)
        '    <None Include="' + $include + '">'
        $filter = ConvertTo-ProjectToolsXml (Get-ProjectToolsFilter $file $Component.filters $SharedPath)
        '      <__UniversalDevKitFilter>' + $filter + '</__UniversalDevKitFilter>'
        '    </None>'
    }
    '  </ItemGroup>'
}

function New-ProjectToolsApplicationSharedProject($Model, $Component, [string]$Path, [string]$Guid) {
    $includeDirectories = @(foreach ($directory in $Component.compile.includeDirectories) {
        Get-ProjectToolsRelativeImport $Model $Path $directory
    })
    $lines = @(
        '<?xml version="1.0" encoding="utf-8"?>'
        '<!-- Generated by ProjectTools. Edit the component description. -->'
        '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">'
        '  <PropertyGroup Label="Globals">'
        '    <HasSharedItems>true</HasSharedItems>'
        "    <ItemsProjectGuid>$Guid</ItemsProjectGuid>"
        '  </PropertyGroup>'
        '  <ItemGroup>'
    )
    foreach ($group in @(@{ Type = 'ClInclude'; Files = $Component.headers }, @{ Type = 'ClCompile'; Files = $Component.sources })) {
        foreach ($file in $group.Files | Sort-Object -CaseSensitive) {
            $include = ConvertTo-ProjectToolsXml (Get-ProjectToolsRelativeImport $Model $Path $file)
            $filter = ConvertTo-ProjectToolsXml (Get-ProjectToolsFilter $file $Component.filters $Path)
            $lines += '    <' + $group.Type + ' Include="' + $include + '">'
            $lines += '      <__UniversalDevKitFilter>' + $filter + '</__UniversalDevKitFilter>'
            if ($group.Type -eq 'ClCompile' -and $includeDirectories.Count) {
                $lines += '      <AdditionalIncludeDirectories>' + (ConvertTo-ProjectToolsXml ($includeDirectories -join ';')) +
                    ';%(AdditionalIncludeDirectories)</AdditionalIncludeDirectories>'
            }
            $lines += '    </' + $group.Type + '>'
        }
    }
    $lines += '  </ItemGroup>'
    $lines += @(Get-ProjectToolsBuildItems $Model $Component $Path)
    $lines += '</Project>'
    return $lines -join "`n"
}

function New-ProjectToolsApplicationProject($Model, $Component, [string]$Path, [string]$SharedPath) {
    $configurations = foreach ($configuration in $Model.Settings.configurations) {
        foreach ($platform in $Model.Settings.platforms) {
            '    <ProjectConfiguration Include="' + $configuration + '|' + $platform + '">'
            '      <Configuration>' + $configuration + '</Configuration>'
            '      <Platform>' + $platform + '</Platform>'
            '    </ProjectConfiguration>'
        }
    }
    $properties = Get-ProjectToolsApplicationProperties $Component @('ProjectGuid', 'Keyword', 'WindowsTargetPlatformVersion', 'UniversalDevKitGitHubVersion')
    if ($Component.githubVersion) {
        $properties = @('    <UniversalDevKitGitHubVersion>' + (ConvertTo-ProjectToolsXml $Component.githubVersion) + '</UniversalDevKitGitHubVersion>') + @($properties)
    }
    $nativeProps = if ($Model.Settings.PSObject.Properties['nativeProps']) {
        $Model.Settings.nativeProps
    } elseif ($Model.Profile -eq 'udk' -or $Model.Manifest.schemaVersion -lt 6) {
        'Projects/MsBuild/BuildLayout.props'
    }
    $props = foreach ($file in @($Component.buildExtensions.msbuildProps) + @($nativeProps) + @($Model.Settings.props)) {
        if ($file) {
            '  <Import Project="' + (ConvertTo-ProjectToolsXml (Get-ProjectToolsRelativeImport $Model $Path $file)) + '" />'
        }
    }
    $targets = foreach ($file in @($Component.buildExtensions.msbuildTargets) + @($Model.Settings.targets)) {
        if ($file) {
            '  <Import Project="' + (ConvertTo-ProjectToolsXml (Get-ProjectToolsRelativeImport $Model $Path $file)) + '" />'
        }
    }
    $standard = if ($Component.requirements.cxxStandard -eq 23) {
        'stdcpplatest'
    } else {
        'stdcpp20'
    }
    $template = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '../Templates/Application.vcxproj.in'))
    $values = @{
        CONFIGURATIONS = $configurations -join "`n"
        GUID = ([Guid]$Component.msbuildGuid).ToString('B').ToUpperInvariant()
        PROPERTIES = $properties -join "`n"
        PROPS = $props -join "`n"
        STANDARD = $standard
        SHARED = ConvertTo-ProjectToolsXml (Get-ProjectToolsRelativeImport $Model $Path $SharedPath)
        TARGETS = $targets -join "`n"
    }
    return [regex]::Replace($template, '@([A-Z]+)@', {
        param($match) $values[$match.Groups[1].Value]
    })
}

function Get-ProjectToolsDotNetLocation($Model, $Component) {
    Get-ProjectToolsLocation $Model $Component '' '.csproj'
}

function New-ProjectToolsDotNetProject($Model, $Component, [string]$Path) {
    $reserved = if ($Component.projectType -eq 'wpf') {
        @('ProjectGuid', 'OutputType', 'UseWPF', 'Nullable')
    }
        elseif ($Component.projectType -eq 'classLibrary') {
            @('ProjectGuid', 'OutputType', 'EnableDefaultNoneItems')
        }
        else {
            @('ProjectGuid', 'GeneratePkgDefFile', 'CreateVsixContainer', 'IncludeAssemblyInVSIXContainer', 'VSSDKTargetPlatformVersion', 'VSSDKBuildToolsAutoSetup', 'LangVersion')
        }
    $reserved += @('EnableDefaultCompileItems', 'EnableDefaultPageItems', 'EnableDefaultApplicationDefinition')
    if ($Component.version) {
        $reserved += 'UniversalDevKitVsixVersion'
    }
    $properties = Get-ProjectToolsApplicationProperties $Component $reserved
    if ($Component.version) {
        $properties = @('    <UniversalDevKitVsixVersion>' + (ConvertTo-ProjectToolsXml $Component.version) + '</UniversalDevKitVsixVersion>') + @($properties)
    }
    $directory = Split-Path -Parent (Resolve-ProjectToolsPath $Model.Root $Path)
    $sourceFiles = @($Component.sources | Sort-Object -CaseSensitive)
    $buildExtensions = @($Component.buildExtensions.msbuildProps, $Component.buildExtensions.msbuildTargets) |
        Where-Object {
            $_
        } | Select-Object -Unique
    $links = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
    $filterItems = foreach ($repositoryPath in ($sourceFiles + @($buildExtensions))) {
        $file = Resolve-ProjectToolsPath $Model.Root $repositoryPath
        $relative = Get-ProjectToolsRelativePath $directory $file
        $outsideProject = $relative -match '^\.\.(?:\\|$)'
        $isBuildExtension = $repositoryPath -in $buildExtensions
        $folder = Get-ProjectToolsFilter $repositoryPath $Component.filters $Path
        $link = [IO.Path]::GetFileName($file)
        if ($folder) {
            $link = $folder + '\' + $link
        }
        if ($links.ContainsKey($link)) {
            throw "Duplicate virtual path '$link' in $($Component.name): '$($links[$link])' and '$repositoryPath'."
        }
        $links.Add($link, $repositoryPath)
        $link = ConvertTo-ProjectToolsXml $link
        $include = ConvertTo-ProjectToolsXml $relative
        if ($isBuildExtension) {
            $operation = if ($outsideProject) {
                'Include'
            } else {
                'Update'
            }
            '    <None ' + $operation + '="' + $include + '" Link="' + $link + '" />'
            continue
        }
        $type = switch ([IO.Path]::GetExtension($file)) {
            '.cs' {
                'Compile'
            }
            '.xaml' {
                if ([IO.Path]::GetFileName($file) -ieq 'App.xaml') {
                    'ApplicationDefinition'
                } else {
                    'Page'
                }
            }
        }
        if (-not $outsideProject) {
            '    <None Remove="' + $include + '" />'
        }
        '    <' + $type + ' Include="' + $include + '" Link="' + $link + '" />'
    }
    $filters = if ($filterItems) {
        (@('  <ItemGroup>') + $filterItems + '  </ItemGroup>') -join "`n"
    }
    $imports = foreach ($file in @($Model.Settings.props) + @($Component.buildExtensions.msbuildProps, $Component.buildExtensions.msbuildTargets) + @($Model.Settings.targets)) {
        if ($file) {
            '  <Import Project="' + (ConvertTo-ProjectToolsXml (Get-ProjectToolsRelativeImport $Model $Path $file)) + '" />'
        }
    }
    $runtimeReferences = foreach ($runtimeProject in $Component.runtimeProjects) {
        $runtimePath = Get-ProjectToolsLocation $Model $runtimeProject 'Dynamic'
        '    <ProjectReference Include="' + (ConvertTo-ProjectToolsXml (Get-ProjectToolsRelativePath $directory (Join-Path $Model.Root $runtimePath))) +
            '" ReferenceOutputAssembly="false" SkipGetTargetFrameworkProperties="true" />'
    }
    $references = if ($runtimeReferences) {
        (@('  <ItemGroup Condition="''$(BuildingInsideVisualStudio)'' == ''true''">') + $runtimeReferences + '  </ItemGroup>') -join "`n"
    }
    $templateName = switch ($Component.projectType) {
        'wpf' {
            'Application.Wpf.csproj.in'
        }
        'vsix' {
            'Application.Vsix.csproj.in'
        }
        'classLibrary' {
            'Library.CSharp.csproj.in'
        }
    }
    $template = [IO.File]::ReadAllText((Join-Path $PSScriptRoot "../Templates/$templateName"))
    $values = @{ PROPERTIES = $properties -join "`n"; FILTERS = $filters; IMPORTS = $imports -join "`n"; REFERENCES = $references }
    return [regex]::Replace($template, '@([A-Z]+)@', {
        param($match) $values[$match.Groups[1].Value]
    })
}

function New-ProjectToolsMsBuildPlan($Model, $UdkPlan) {
    $plan = [Collections.Generic.List[object]]::new()
    $projects = [Collections.Generic.List[object]]::new()
    foreach ($update in $UdkPlan) {
        $plan.Add($update)
    }
    $byName = @{}
    foreach ($component in $Model.Components.Values) {
        $byName[$component.name] = $component
    }
    $registry = @{}
    foreach ($component in $Model.Components.Values) {
        $registry[$component.name] = [pscustomobject]@{
            Kind = $component.kind; StateScope = $component.stateScope
            Dependencies = @($component.dependencies | Where-Object {
                $_
            } | ForEach-Object {
                [pscustomobject]@{ Component = $_.component; Visibility = $_.visibility; Linkage = $_.linkage }
            })
        }
    }
    foreach ($component in $Model.Components.Values) {
        $mode = if ($component.stateScope -eq 'process') {
            'Dynamic'
        } else {
            'Shared'
        }
        $null = Resolve-UdkLinkageGraph @($component.name) @{ $component.name = $mode } $registry
    }
    function AddOutput([string]$Path, [string]$Content) {
        $absolute = Resolve-ProjectToolsPath $Model.Root $Path
        $content = $Content.TrimEnd([char[]]"`r`n")
        foreach ($existing in @($plan | Where-Object Path -eq $absolute)) {
            [void]$plan.Remove($existing)
        }
        $original = if (Test-Path -LiteralPath $absolute) {
            [IO.File]::ReadAllText($absolute)
        } else {
            $null
        }
        $plan.Add([pscustomobject]@{ Path = $absolute; RelativePath = $Path; Content = $content; Original = $original })
    }
    foreach ($component in $Model.Components.Values) {
        $variants = if ($component.kind -eq 'headerOnly') {
            @()
        } elseif ($component.variants) {
            @($component.variants | ForEach-Object {
                (Get-Culture).TextInfo.ToTitleCase($_)
            })
        } elseif ($component.stateScope -eq 'process') {
            @('Dynamic')
        } else {
            @('Static', 'Dynamic')
        }
        if (@($variants | Where-Object {
            $_ -notin @('Static', 'Dynamic')
        }).Count -or @($variants | Select-Object -Unique).Count -ne $variants.Count) {
            throw 'Invalid or duplicate binary variant.'
        }
        if ($component.stateScope -eq 'process' -and 'Static' -in $variants) {
            throw 'Process state requires Dynamic.'
        }
        $sharedPath = Get-ProjectToolsLocation $Model $component 'Shared'
        $projects.Add([pscustomobject]@{ Path = $sharedPath; Guid = $component.msbuildGuid; Variant = 'Shared'; Component = $component.name })
        $sharedItems = [Collections.Generic.List[object]]::new()
        if (-not ($Model.Integration -or $Model.Profile -eq 'udk')) {
            $lines = [Collections.Generic.List[string]]::new()
            $lines.Add('<?xml version="1.0" encoding="utf-8"?>')
            $lines.Add('<!-- Generated by ProjectTools. Edit the component registry and its descriptions. -->')
            $lines.Add('<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">')
            $lines.Add('  <PropertyGroup Label="Globals"><HasSharedItems>true</HasSharedItems><ItemsProjectGuid>' + $component.msbuildGuid + '</ItemsProjectGuid></PropertyGroup>')
            if ($component.buildExtensions.msbuildProps) {
                $lines.Add('  <Import Project="' + (ConvertTo-ProjectToolsXml (Get-ProjectToolsRelativeImport $Model $sharedPath $component.buildExtensions.msbuildProps)) + '" />')
            }
            $lines.Add('  <ItemDefinitionGroup><ClCompile>')
            $standard = if ($component.requirements.cxxStandard -eq 23) {
                'stdcpplatest'
            } else {
                'stdcpp20'
            }
            $lines.Add('    <LanguageStandard>' + $standard + '</LanguageStandard><ExceptionHandling>Sync</ExceptionHandling><AdditionalOptions>/utf-8 %(AdditionalOptions)</AdditionalOptions>')
            $includes = @($component.compile.includeDirectories | ForEach-Object {
                Get-ProjectToolsRelativeImport $Model $sharedPath $_
            })
            if ($includes.Count) {
                $lines.Add('    <AdditionalIncludeDirectories>' + (ConvertTo-ProjectToolsXml ($includes -join ';')) + ';%(AdditionalIncludeDirectories)</AdditionalIncludeDirectories>')
            }
            if ($component.compile.preprocessorDefinitions) {
                $lines.Add('    <PreprocessorDefinitions>' + (ConvertTo-ProjectToolsXml ($component.compile.preprocessorDefinitions -join ';')) + ';%(PreprocessorDefinitions)</PreprocessorDefinitions>')
            }
            if ($component.compile.precompiledHeader -eq 'notUsing') {
                $lines.Add('    <PrecompiledHeader>NotUsing</PrecompiledHeader>')
            }
            $lines.Add('  </ClCompile></ItemDefinitionGroup>')
            $lines.Add('  <ItemGroup>')
            foreach ($group in @(@{ Type = 'ClInclude'; Files = $component.headers }, @{ Type = 'ClCompile'; Files = $component.sources })) {
                foreach ($file in $group.Files) {
                    $include = Get-ProjectToolsRelativeImport $Model $sharedPath $file
                    $filter = Get-ProjectToolsFilter $file $component.filters $sharedPath
                    $sharedItems.Add(@{ Type = $group.Type; Include = $include; Filter = $filter })
                    $lines.Add('    <' + $group.Type + ' Include="' + (ConvertTo-ProjectToolsXml $include) + '" />')
                }
            }
            foreach ($file in @($component.buildExtensions.msbuildProps, $component.buildExtensions.msbuildTargets) | Where-Object {
                $_
            } | Select-Object -Unique) {
                $include = Get-ProjectToolsRelativeImport $Model $sharedPath $file
                $sharedItems.Add(@{ Type = 'None'; Include = $include; Filter = (Get-ProjectToolsFilter $file $component.filters $sharedPath) })
                $lines.Add('    <None Include="' + (ConvertTo-ProjectToolsXml $include) + '" />')
            }
            $lines.Add('  </ItemGroup>')
            $lines.Add('</Project>')
            AddOutput $sharedPath ($lines -join "`n")
            $filters = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            foreach ($item in $sharedItems) {
                $filter = $item.Filter; while ($filter) {
                    [void]$filters.Add($filter); $filter = Split-Path -Parent $filter
                }
            }
            $filterLines = @('<?xml version="1.0" encoding="utf-8"?>', '<!-- Generated by ProjectTools. Edit component file selections. -->', '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">', '  <ItemGroup>')
            foreach ($filter in @($filters | Sort-Object)) {
                $filterLines += '    <Filter Include="' + (ConvertTo-ProjectToolsXml $filter) + '" />'
            }
            foreach ($item in $sharedItems) {
                $element = '    <' + $item.Type + ' Include="' + (ConvertTo-ProjectToolsXml $item.Include) + '"'
                if ($item.Filter) {
                    $element += '><Filter>' + (ConvertTo-ProjectToolsXml $item.Filter) + '</Filter></' + $item.Type + '>'
                } else {
                    $element += ' />'
                }
                $filterLines += $element
            }
            $filterLines += @('  </ItemGroup>', '</Project>')
            AddOutput ($sharedPath + '.filters') ($filterLines -join "`n")
        }
        foreach ($variant in $variants) {
            $path = Get-ProjectToolsLocation $Model $component $variant
            $absolute = Join-Path $Model.Root $path
            $guid = Get-ProjectToolsGuid (([Guid]$component.msbuildGuid).ToString('D') + ':' + $variant)
            if (Test-Path -LiteralPath $absolute) {
                [xml]$old = [IO.File]::ReadAllText($absolute)
                $nodes = @($old.SelectNodes('/*[local-name()="Project"]/*[local-name()="PropertyGroup"]/*[local-name()="ProjectGuid"]'))
                if ($nodes.Count -ne 1) {
                    throw "Invalid existing project GUID: $path"
                }
                $guid = '{' + ([Guid]$nodes[0].InnerText).ToString().ToUpperInvariant() + '}'
            }
            $projects.Add([pscustomobject]@{ Path = $path; Guid = $guid; Variant = $variant; Component = $component.name })
            $template = Get-ProjectToolsNativeProjectTemplate $Model $component $path
            $integration = $Model.Integration -or $Model.Profile -eq 'udk'
            $definitions = @($component.msbuild.dynamicDefinitions | Where-Object {
                $_
            })
            if ($integration -and -not $definitions.Count) {
                $prefix = 'UNIVERSALDEVKIT_' + $component.name.ToUpperInvariant()
                $definitions = @($prefix + '_DYNAMIC'; $prefix + '_EXPORTS')
            }
            $definitionXml = if ($variant -eq 'Dynamic' -and $definitions.Count) {
                '      <PreprocessorDefinitions>' + (ConvertTo-ProjectToolsXml ($definitions -join ';')) + ';%(PreprocessorDefinitions)</PreprocessorDefinitions>'
            } else {
                ''
            }
            $type = if ($variant -eq 'Dynamic') {
                'DynamicLibrary'
            } else {
                'StaticLibrary'
            }
            $content = $template.Replace('@GUID@', $guid.Trim('{}')).Replace('@CONFIGURATION_TYPE@', $type).Replace('@DYNAMIC_DEFINITIONS@', $definitionXml)
            $graph = Resolve-UdkLinkageGraph @($component.name) @{ $component.name = $variant } $registry
            $standard = 20
            foreach ($requiredName in $graph.RequirementComponents) {
                $standard = [Math]::Max($standard, [int]$byName[$requiredName].requirements.cxxStandard)
            }
            if ($standard -eq 23) {
                $content = $content.Replace('stdcpp20', 'stdcpplatest')
            }

            if (-not $integration) {
                $content = $content.Replace('</ConfigurationType>', "</ConfigurationType>`n    <CharacterSet>Unicode</CharacterSet>")
                $references = foreach ($dependencyName in $graph.ResolvedComponents) {
                    if ($dependencyName -eq $component.name -or $registry[$dependencyName].Kind -eq 'headerOnly') {
                        continue
                    }
                    $dependencyPath = Get-ProjectToolsLocation $Model $byName[$dependencyName] $graph.ResolvedModes[$dependencyName]
                    '  <ItemGroup><ProjectReference Include="' + (ConvertTo-ProjectToolsXml (Get-ProjectToolsRelativeImport $Model $path $dependencyPath)) + '" /></ItemGroup>'
                }
                $cppTargets = '  <Import Project="$(VCTargetsPath)\Microsoft.Cpp.targets" />'
                $content = $content.Replace($cppTargets, ((@($references | Where-Object {
                    $_
                }) + $cppTargets) -join "`n"))
                $targets = foreach ($file in @($component.buildExtensions.msbuildTargets) + @($Model.Settings.targets) | Where-Object {
                    $_
                }) {
                    '  <Import Project="' + (ConvertTo-ProjectToolsXml (Get-ProjectToolsRelativeImport $Model $path $file)) + '" />'
                }
                $content = $content.Replace('</Project>', ((@($targets | Where-Object {
                    $_
                }) + '</Project>') -join "`n"))
                AddOutput ($path + '.filters') ($filterLines -join "`n")
            }
            AddOutput $path $content
        }
        if (($Model.Integration -or $Model.Profile -eq 'udk') -and $component.kind -eq 'headerOnly') {
            $path = Get-ProjectToolsLocation $Model $component 'HeaderCheck'
            $guid = Get-ProjectToolsGuid (([Guid]$component.msbuildGuid).ToString('D') + ':HeaderCheck')
            $projects.Add([pscustomobject]@{ Path = $path; Guid = $guid; Variant = 'HeaderCheck'; Component = $component.name })
        }
    }
    foreach ($component in $Model.ManagedLibraries.Values) {
        $guid = ([Guid]$component.msbuildGuid).ToString('B').ToUpperInvariant()
        $path = Get-ProjectToolsDotNetLocation $Model $component
        $projects.Add([pscustomobject]@{ Path = $path; Guid = $guid; Variant = 'DotNet'; Component = $component.name })
        AddOutput $path (New-ProjectToolsDotNetProject $Model $component $path)
    }
    foreach ($component in $Model.Applications.Values) {
        $guid = ([Guid]$component.msbuildGuid).ToString('B').ToUpperInvariant()
        if ($component.language -ceq 'csharp') {
            $path = Get-ProjectToolsDotNetLocation $Model $component
            $projects.Add([pscustomobject]@{ Path = $path; Guid = $guid; Variant = 'DotNet'; Component = $component.name })
            AddOutput $path (New-ProjectToolsDotNetProject $Model $component $path)
            continue
        }
        $path = Get-ProjectToolsLocation $Model $component 'Application'
        $projects.Add([pscustomobject]@{ Path = $path; Guid = $guid; Variant = 'Application'; Component = $component.name })
        $sharedPath = Get-ProjectToolsLocation $Model $component 'Shared'
        $sharedGuid = Get-ProjectToolsGuid (([Guid]$guid).ToString('D') + ':Shared')
        $projects.Add([pscustomobject]@{ Path = $sharedPath; Guid = $sharedGuid; Variant = 'Shared'; Component = $component.name })
        AddOutput $sharedPath (New-ProjectToolsApplicationSharedProject $Model $component $sharedPath $sharedGuid)
        AddOutput $path (New-ProjectToolsApplicationProject $Model $component $path $sharedPath)
    }
    if (@($projects.Guid | Sort-Object -Unique).Count -ne $projects.Count) {
        throw 'Duplicate project GUID.'
    }
    if ($Model.Manifest.schemaVersion -ge 6) {
        foreach ($project in $projects) {
            $component = switch ($project.Variant) {
                'DotNet' {
                    @($Model.ManagedLibraries.Values) + @($Model.Applications.Values) | Where-Object {
                        $_.name -eq $project.Component -and $_.language -eq 'csharp'
                    }
                }
                default {
                    @($Model.Components.Values) + @($Model.Applications.Values) | Where-Object {
                        $_.name -eq $project.Component -and $_.language -ne 'csharp'
                    }
                }
            }
            $project | Add-Member SolutionFolder (Get-ProjectToolsLayout $Model $component $project.Variant 'solutionFolder')
        }
    }
    if (@($projects.Path | Sort-Object -Unique).Count -ne $projects.Count) {
        throw 'Duplicate project path.'
    }
    return [pscustomobject]@{ Files = $plan; Projects = $projects }
}