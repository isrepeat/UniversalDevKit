param(
    [string]$RepositoryRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [switch]$Check,
    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'FormatXmlAttributes.ps1')
. (Join-Path $PSScriptRoot 'Modules/Module.Udk.Connection/Private/Requirements.ps1')
$repositoryPath = [IO.Path]::GetFullPath($RepositoryRoot)
$manifest = Get-Content -LiteralPath (Join-Path $repositoryPath 'Components.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1 -or ($manifest.schemaVersion -isnot [int] -and $manifest.schemaVersion -isnot [long])) {
    throw 'Unsupported Components.json schemaVersion.'
}
foreach ($field in $manifest.PSObject.Properties.Name) {
    if ($field -notin @('schemaVersion', 'includes')) {
        throw "Unsupported manifest field: $field"
    }
}
if ($manifest.includes -isnot [Array] -or -not $manifest.includes.Count) {
    throw 'Components.json must contain a nonempty includes array.'
}
$updates = [Collections.Generic.List[object]]::new()
$guids = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$includePaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$componentGraph = @{}
$binaryComponentRegistry = @{}

function EscapeXml([string]$Value) {
    return [Security.SecurityElement]::Escape($Value)
}

function ValidateFile([string]$Path, [string]$Root) {
    # Allow explicit component paths only, without wildcards, macros or repository traversal.
    if (-not $Path.StartsWith($Root, [StringComparison]::Ordinal) -or
        $Path -match '[\\:$@%*?;\r\n]' -or
        @($Path.Split('/') | Where-Object { $_ -in @('', '.', '..') }).Count) {
        throw "Invalid component file path: $Path"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $repositoryPath $Path) -PathType Leaf)) {
        throw "Component file does not exist: $Path"
    }
}

function ValidateFilterPath($Value, [string]$Label) {
    if ($Value -isnot [string] -or ($Value -ne '' -and
        ($Value -match '[\\:$@%*?;\r\n]' -or
         @($Value.Split('/') | Where-Object { $_ -in @('', '.', '..') -or $_ -ne $_.Trim() }).Count))) {
        throw "Invalid filter path: $Label"
    }
}

function ValidateFilterSettings($Settings, $Component) {
    if ($null -eq $Settings) {
        return
    }
    if ($Settings -isnot [pscustomobject]) {
        throw 'filters must be an object.'
    }
    foreach ($field in $Settings.PSObject.Properties.Name) {
        if ($field -notin @('roots', 'files')) {
            throw "Unsupported filters field: $field"
        }
    }
    if ($Settings.PSObject.Properties['roots']) {
        if ($Settings.roots -isnot [Array]) {
            throw 'filters.roots must be an array.'
        }
        $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($rule in $Settings.roots) {
            if ($rule -isnot [pscustomobject]) {
                throw 'Filter root must be an object.'
            }
            foreach ($field in $rule.PSObject.Properties.Name) {
                if ($field -notin @('path', 'filter')) {
                    throw "Unsupported filter root field: $field"
                }
            }
            ValidateFilterPath $rule.path 'roots.path'
            ValidateFilterPath $rule.filter 'roots.filter'
            if ($rule.path -eq '' -or -not $seen.Add($rule.path)) {
                throw "Empty or duplicate filter root: $($rule.path)"
            }
        }
    }
    if ($Settings.PSObject.Properties['files']) {
        if ($Settings.files -isnot [pscustomobject]) {
            throw 'filters.files must be an object.'
        }
        $knownFiles = @($Component.headers) + @($Component.sources)
        if ($Component.platformSources) {
            foreach ($platformEntry in $Component.platformSources.PSObject.Properties) { $knownFiles += @($platformEntry.Value) }
        }
        foreach ($entry in $Settings.files.PSObject.Properties) {
            if ($entry.Name -cnotin $knownFiles) {
                throw "Unknown filters.files entry: $($entry.Name)"
            }
            ValidateFilterPath $entry.Value $entry.Name
        }
    }
}

function GetComponentFilter([string]$Path, $Settings) {
    # File overrides take precedence; an empty value places the file at the project root.
    if ($null -ne $Settings -and $null -ne $Settings.files) {
        $entry = $Settings.files.PSObject.Properties[$Path]
        if ($entry) {
            return $entry.Value.Replace('/', '\')
        }
    }
    $mapped = $Path
    if ($null -ne $Settings) {
        $best = $null
        foreach ($rule in $Settings.roots) {
            if ($Path.StartsWith($rule.path + '/', [StringComparison]::Ordinal) -and
                ($null -eq $best -or $rule.path.Length -gt $best.path.Length)) {
                $best = $rule
            }
        }
        if ($null -ne $best) {
            $mapped = $Path.Substring($best.path.Length + 1)
            if ($best.filter -ne '') {
                $mapped = $best.filter + '/' + $mapped
            }
        }
    }
    return [IO.Path]::GetDirectoryName($mapped.Replace('/', '\'))
}

foreach ($includePath in $manifest.includes) {
    # Resolve includes from root Components.json; nested includes are unsupported.
    if ($includePath -isnot [string] -or $includePath -match '[\\:$@%*?;\r\n]' -or
        @($includePath.Split('/') | Where-Object { $_ -in @('', '.', '..') }).Count -or
        [IO.Path]::GetExtension($includePath) -cne '.json') {
        throw "Invalid component include path: $includePath"
    }
    if (-not $includePaths.Add($includePath)) {
        throw "Duplicate component include: $includePath"
    }
    $component = Get-Content -LiteralPath (Join-Path $repositoryPath $includePath) -Raw -Encoding UTF8 | ConvertFrom-Json
    $name = $component.name
    if ($name -isnot [string]) {
        throw "Component name must be a string: $includePath"
    }
    if ($name -notmatch '^[A-Z][A-Za-z0-9]*$') {
        throw "Invalid component name: $name"
    }
    if (-not $names.Add($name)) {
        throw "Duplicate component name: $name"
    }
    # Reject unknown fields; dependencies and platforms require explicit generator support.
    foreach ($field in $component.PSObject.Properties.Name) {
        if ($field -notin @('name', 'msbuildGuid', 'headers', 'sources', 'filters', 'dependencies', 'supportedPlatforms', 'platformSources', 'stateScope', 'requirements', 'platformRequirements', 'buildExtensions', 'kind')) {
            throw "Unsupported field ${name}: $field"
        }
    }
    $guid = [Guid]::Empty
    $kind = if ($component.PSObject.Properties['kind']) { $component.kind } else { 'compiled' }
    if ($kind -cnotin @('compiled', 'headerOnly')) { throw "Invalid component kind: $name" }
    if ($kind -eq 'headerOnly' -and ($component.sources.Count -or $component.platformSources -or $component.buildExtensions -or $component.stateScope -eq 'process')) {
        throw "Header-only component cannot contain sources, build extensions or process state: $name"
    }
    if ($component.PSObject.Properties['stateScope'] -and $component.stateScope -cnotin @('module', 'process')) {
        throw "Invalid stateScope for component: $name"
    }
    if ($component.msbuildGuid -isnot [string] -or $component.msbuildGuid -notmatch '^\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}$' -or
        -not [Guid]::TryParse([string]$component.msbuildGuid, [ref]$guid) -or -not $guids.Add($guid.ToString())) {
        throw "Invalid or duplicate msbuildGuid: $name"
    }
    foreach ($field in @('headers', 'sources')) {
        if ($null -eq $component.$field -or $component.$field -isnot [Array]) {
            throw "${name}.${field} must be an array."
        }
    }
    $dependencies = [Collections.Generic.List[string]]::new()
    if ($component.PSObject.Properties['dependencies']) {
        if ($component.dependencies -isnot [Array]) {
            throw "${name}.dependencies must be an array."
        }
        foreach ($dependency in $component.dependencies) {
            if ($dependency -isnot [pscustomobject]) {
                throw "Invalid dependency in $name"
            }
            foreach ($field in $dependency.PSObject.Properties.Name) {
                if ($field -notin @('component', 'visibility', 'linkage')) {
                    throw "Unsupported dependency field: $field"
                }
            }
            if ($dependency.component -isnot [string] -or $dependency.component -notmatch '^[A-Z][A-Za-z0-9]*$') {
                throw "Invalid dependency component in $name"
            }
            if ($dependency.visibility -cnotin @('private', 'public') -or $dependency.linkage -cnotin @('same', 'static', 'dynamic')) {
                throw "Invalid dependency visibility or linkage in $name"
            }
            if ($dependencies.Contains($dependency.component)) {
                throw "Duplicate dependency in ${name}: $($dependency.component)"
            }
            $dependencies.Add($dependency.component)
        }
    }
    $componentGraph[$name] = $dependencies.ToArray()
    $binaryComponentRegistry[$name] = [pscustomobject]@{
        SharedGuid = $guid
        Kind = $kind
        StateScope = $component.stateScope
        Requirements = Get-UdkRequirementDefinition $component
        Dependencies = @($component.dependencies | Where-Object { $null -ne $_ } | ForEach-Object {
            [pscustomobject]@{ Component = $_.component; Visibility = $_.visibility; Linkage = $_.linkage }
        })
    }
    if ($component.PSObject.Properties['filters'] -and $null -eq $component.filters) {
        throw "${name}.filters must be an object."
    }
    $componentSources = @($component.sources)
    $platformFileConditions = @{}
    if ($component.PSObject.Properties['supportedPlatforms']) {
        if ($component.supportedPlatforms -isnot [Array] -or -not $component.supportedPlatforms.Count) {
            throw "${name}.supportedPlatforms must be a nonempty array."
        }
        foreach ($platform in $component.supportedPlatforms) {
            if ($platform -cnotin @('Windows', 'Linux', 'Android')) {
                throw "Unsupported platform: $platform"
            }
        }
    }
    if ($component.PSObject.Properties['platformSources']) {
        if ($component.platformSources -isnot [pscustomobject]) {
            throw "${name}.platformSources must be an object."
        }
        foreach ($platformEntry in $component.platformSources.PSObject.Properties) {
            if ($platformEntry.Name -cnotin @('Windows', 'Linux', 'Android') -or $platformEntry.Value -isnot [Array]) {
                throw "Invalid platformSources entry: $($platformEntry.Name)"
            }
            if ($component.supportedPlatforms -and $platformEntry.Name -cnotin $component.supportedPlatforms) {
                throw "Platform sources outside supportedPlatforms: $($platformEntry.Name)"
            }
            foreach ($platformFile in $platformEntry.Value) {
                if ($platformFile -isnot [string] -or $platformFileConditions.ContainsKey($platformFile)) {
                    throw "Invalid or duplicate platform source: $platformFile"
                }
                $componentSources += $platformFile
                $platformFileConditions[$platformFile] = "'`$(UniversalDevKitTargetOS)' == '$($platformEntry.Name)'"
            }
        }
    }
    if ($component.PSObject.Properties['buildExtensions']) {
        if ($component.buildExtensions -isnot [pscustomobject]) { throw "${name}.buildExtensions must be an object." }
        foreach ($extension in $component.buildExtensions.PSObject.Properties) {
            if ($extension.Name -cnotin @('cmake', 'msbuildProps', 'msbuildTargets') -or $extension.Value -isnot [string]) {
                throw "Invalid build extension: ${name}.$($extension.Name)"
            }
            ValidateFile $extension.Value 'Projects/'
            $expectedExtension = @{ cmake = '.cmake'; msbuildProps = '.props'; msbuildTargets = '.targets' }[$extension.Name]
            if ([IO.Path]::GetExtension($extension.Value) -cne $expectedExtension) { throw "Invalid build extension suffix: $($extension.Value)" }
        }
    }
    ValidateFilterSettings $component.filters $component
    $files = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $objects = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add('<?xml version="1.0" encoding="utf-8"?>')
    $lines.Add('<!-- Generated by GenerateComponentProjects.ps1. Edit the component registry. -->')
    $lines.Add('<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">')
    $lines.Add('  <PropertyGroup Label="Globals">')
    $lines.Add('    <HasSharedItems>true</HasSharedItems>')
    $lines.Add('    <ItemsProjectGuid>{' + $guid.ToString().ToUpperInvariant() + '}</ItemsProjectGuid>')
    $lines.Add('  </PropertyGroup>')
    $lines.Add('  <Import Project="$(MSBuildThisFileDirectory)..\UniversalDevKit.props" Condition="''$(__IsUniversalDevKitPublicPropsImported)'' != ''true''" />')
    if ($component.buildExtensions.msbuildProps) {
        $lines.Add('  <Import Project="' + (EscapeXml ('$(MSBuildThisFileDirectory)..\..\..\' + $component.buildExtensions.msbuildProps.Replace('/', '\'))) + '" />')
    }
    $lines.Add('  <ItemDefinitionGroup>')
    $lines.Add('    <ClCompile>')
    $lines.Add('      <AdditionalIncludeDirectories>$(MSBuildThisFileDirectory)..\..\..\Includes\' + $name + ';%(AdditionalIncludeDirectories)</AdditionalIncludeDirectories>')
    $lines.Add('    </ClCompile>')
    $lines.Add('  </ItemDefinitionGroup>')
    $lines.Add('  <ItemGroup>')
    foreach ($path in $component.headers) {
        if ($path -isnot [string]) {
            throw "${name}.headers must contain strings."
        }
        ValidateFile $path "Includes/$name/UniversalDevKit/$name/"
        if (-not $files.Add($path)) {
            throw "Duplicate component file: $path"
        }
        $include = EscapeXml ('$' + '(MSBuildThisFileDirectory)..\..\..\' + $path.Replace('/', '\'))
        $lines.Add('    <ClInclude Include="' + $include + '">')
        $lines.Add('      <__UniversalDevKitFilter>' + (EscapeXml (GetComponentFilter $path $component.filters)) + '</__UniversalDevKitFilter>')
        $lines.Add('    </ClInclude>')
    }
    foreach ($path in $componentSources) {
        if ($path -isnot [string]) {
            throw "${name}.sources must contain strings."
        }
        ValidateFile $path "Sources/$name/"
        if (-not $files.Add($path)) {
            throw "Duplicate component file: $path"
        }
        if ([IO.Path]::GetExtension($path) -cne '.cpp') {
            throw "Expected .cpp source: $path"
        }
        $relative = $path.Substring("Sources/$name/".Length)
        $object = [IO.Path]::ChangeExtension($relative, '.obj').Replace('/', '\')
        if (-not $objects.Add($object)) {
            throw "Duplicate object path: $path"
        }
        $include = EscapeXml ('$' + '(MSBuildThisFileDirectory)..\..\..\' + $path.Replace('/', '\'))
        $conditionAttribute = if ($platformFileConditions.ContainsKey($path)) {
            ' Condition="' + (EscapeXml $platformFileConditions[$path]) + '"'
        } else {
            ''
        }
        $lines.Add('    <ClCompile Include="' + $include + '"' + $conditionAttribute + '>')
        $lines.Add('      <__UniversalDevKitFilter>' + (EscapeXml (GetComponentFilter $path $component.filters)) + '</__UniversalDevKitFilter>')
        $lines.Add('      <PrecompiledHeader>NotUsing</PrecompiledHeader>')
        $lines.Add('      <ObjectFileName>$(IntDir)UniversalDevKit\' + $name + '\' + (EscapeXml $object) + '</ObjectFileName>')
        $lines.Add('    </ClCompile>')
    }
    $lines.Add('  </ItemGroup>')
    if ($component.stateScope -eq 'process') {
        # The DLL needs its source list, but consumers must not compile it directly.
        $lines.Add('  <Target Name="__UniversalDevKitValidate' + $name + 'StateScope" BeforeTargets="PrepareForBuild">')
        $lines.Add('    <Error Condition="''$(ConfigurationType)'' != ''DynamicLibrary'' or ''$(MSBuildProjectName)'' != ''UniversalDevKit.' + $name + '.Dynamic''" Text="UniversalDevKit.' + $name + ' has process state; use its Dynamic project." />')
        $lines.Add('  </Target>')
    }
    if ($component.supportedPlatforms) {
        $unsupportedCondition = (@($component.supportedPlatforms | ForEach-Object { "'`$(UniversalDevKitTargetOS)' != '$_'" }) -join ' and ')
        $lines.Add('  <Target Name="__UniversalDevKitValidate' + $name + 'Platform" BeforeTargets="PrepareForBuild">')
        $lines.Add('    <Error Condition="' + (EscapeXml $unsupportedCondition) + '" Text="Unsupported platform for UniversalDevKit.' + $name + ': $(UniversalDevKitTargetOS)" />')
        $lines.Add('  </Target>')
    }
    $lines.Add((Get-UdkRequirementItemsXml $name $binaryComponentRegistry[$name].Requirements $true $true $true))
    $lines.Add('  <Import Project="$(MSBuildThisFileDirectory)..\UniversalDevKit.Requirements.targets" Condition="''$(__IsUniversalDevKitRequirementsImported)'' != ''true''" />')
    if ($component.buildExtensions.msbuildTargets) {
        $lines.Add('  <Import Project="' + (EscapeXml ('$(MSBuildThisFileDirectory)..\..\..\' + $component.buildExtensions.msbuildTargets.Replace('/', '\'))) + '" />')
    }
    $lines.Add('</Project>')
    $relativePath = "Projects/MsBuild/$name/UniversalDevKit.$name.Shared.vcxitems"
    $targetPath = Join-Path $repositoryPath $relativePath
    $content = $lines -join "`n"
    $original = if (Test-Path -LiteralPath $targetPath) {
        [IO.File]::ReadAllText($targetPath)
    } else {
        $null
    }
    # CRLF/LF differences alone do not require rewriting.
    if ($null -eq $original -or $original.Replace("`r`n", "`n") -cne $content) {
        $updates.Add([pscustomobject]@{ Path = $targetPath; RelativePath = $relativePath; Content = $content; Original = $original })
    }
}

# Resolve dependency closure before writing; cycles and unknown names stop generation.
function GetDependencyClosure([string]$Name, [string[]]$Stack) {
    if ($Name -cin $Stack) {
        throw ('Component dependency cycle: ' + (($Stack + $Name) -join ' -> '))
    }
    if ($Name -cnotin @($componentGraph.Keys)) {
        throw "Unknown dependency component: $Name"
    }
    $result = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    [void]$result.Add($Name)
    foreach ($dependency in $componentGraph[$Name]) {
        foreach ($resolved in (GetDependencyClosure $dependency @($Stack + $Name))) { [void]$result.Add($resolved) }
    }
    return @($result | Sort-Object)
}
$closures = @{}
$componentNames = @($componentGraph.Keys | Sort-Object)
foreach ($name in $componentNames) { $closures[$name] = @(GetDependencyClosure $name @()) }
foreach ($name in $componentNames) {
    if ($binaryComponentRegistry[$name].Kind -eq 'headerOnly') {
        foreach ($dependency in $binaryComponentRegistry[$name].Dependencies) {
            if ($dependency.Visibility -ne 'public' -or $dependency.Linkage -ne 'same' -or $binaryComponentRegistry[$dependency.Component].Kind -ne 'headerOnly') {
                throw "Header-only dependencies must be public/same and headerOnly: $name"
            }
        }
    }
}

$lines = [Collections.Generic.List[string]]::new()
$lines.Add('<?xml version="1.0" encoding="utf-8"?>')
$lines.Add('<!-- Generated by GenerateComponentProjects.ps1. This file is generated entirely')
$lines.Add('     from Components.json and included descriptions in Projects/Components/.')
$lines.Add('     Do not edit manually: changes are overwritten by the next generation.')
$lines.Add('     To update, edit JSON and run Scripts/GenerateComponentProjects.cmd.')
$lines.Add('')
$lines.Add('     Connect adds UniversalDevKitComponents and an import of this file to the consumer.')
$lines.Add('     MSBuild evaluation includes headers and sources of the selected components')
$lines.Add('     and all transitive dependencies; each Shared project is imported once.')
$lines.Add('     Sources are not copied and compile with the consumer project settings.')
$lines.Add('     The Connect menu uses this registry; selections are validated before building. -->')
$lines.Add('<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">')
$lines.Add('  <Import Project="UniversalDevKit.props" Condition="''$(__IsUniversalDevKitPublicPropsImported)'' != ''true''" />')
$lines.Add('  <ItemGroup>')
$lines.Add('    <__UniversalDevKitAvailableComponent Include="' + ($componentNames -join ';') + '" />')
$lines.Add('    <__UniversalDevKitComponent Include="$(UniversalDevKitComponents)" />')
$lines.Add('  </ItemGroup>')
# Resolve the ProjectOnly Shared graph while preserving explicit dynamic dependencies.
. (Join-Path $PSScriptRoot 'Modules/Module.Udk.Connection/Private/ConnectionPlan.ps1')
$sourceGraphs = @{}
foreach ($rootName in $componentNames) {
    if ($binaryComponentRegistry[$rootName].StateScope -ne 'process') {
        $sourceGraphs[$rootName] = Resolve-UdkLinkageGraph @($rootName) @{ $rootName = 'Shared' } $binaryComponentRegistry
    }
}
function GetSourceCondition([string[]]$Roots) {
    return (@($Roots | ForEach-Object {
        '$([System.String]::Copy('';$(UniversalDevKitComponents);'').Contains('';' + $_ + ';''))'
    }) -join ' Or ')
}
$lines.Add('  <PropertyGroup>')
foreach ($name in $componentNames) {
    $selectors = @($sourceGraphs.Keys | Where-Object { $sourceGraphs[$_].ResolvedModes[$name] -eq 'Shared' } | Sort-Object)
    $lines.Add('    <__HasUniversalDevKit' + $name + '>false</__HasUniversalDevKit' + $name + '>')
    if ($selectors.Count) {
        $lines.Add('    <__HasUniversalDevKit' + $name + ' Condition="' + (GetSourceCondition $selectors) + '">true</__HasUniversalDevKit' + $name + '>')
    }
}
$lines.Add('  </PropertyGroup>')
foreach ($name in $componentNames) {
    if ($binaryComponentRegistry[$name].StateScope -ne 'process') {
        $lines.Add('  <Import Project="' + $name + '\UniversalDevKit.' + $name + '.Shared.vcxitems" Condition="' +
            '''$(__HasUniversalDevKit' + $name + ')'' == ''true''" Label="Shared" />')
    }
    foreach ($variant in @('Static', 'Dynamic')) {
        $selectors = @($sourceGraphs.Keys | Where-Object { $sourceGraphs[$_].ResolvedModes[$name] -eq $variant } | Sort-Object)
        if (-not $selectors.Count) {
            continue
        }
        $condition = GetSourceCondition $selectors
        $lines.Add('  <ItemGroup Condition="' + $condition + '">')
        $lines.Add('    <ProjectReference Include="$(MSBuildThisFileDirectory)' + $name + '\UniversalDevKit.' + $name + '.' + $variant + '.vcxproj">')
        $linkSelectors = @($selectors | Where-Object { $name -cin $sourceGraphs[$_].LinkComponents })
        $lines.Add('      <LinkLibraryDependencies>false</LinkLibraryDependencies>')
        if ($linkSelectors.Count) {
            $lines.Add('      <LinkLibraryDependencies Condition="' + (GetSourceCondition $linkSelectors) + '">true</LinkLibraryDependencies>')
        }
        $lines.Add('    </ProjectReference>')
        if ($variant -eq 'Dynamic') {
            $lines.Add('    <__UniversalDevKitRuntimeProject Include="$(MSBuildThisFileDirectory)' + $name + '\UniversalDevKit.' + $name + '.Dynamic.vcxproj" />')
        }
        $lines.Add('  </ItemGroup>')
        $definitionSelectors = @($selectors | Where-Object { $name -cin $sourceGraphs[$_].DefinitionComponents })
        if ($definitionSelectors.Count) {
            $lines.Add('  <ItemDefinitionGroup Condition="' + (GetSourceCondition $definitionSelectors) + '">')
            $lines.Add('    <ClCompile><AdditionalIncludeDirectories>$(MSBuildThisFileDirectory)..\..\Includes\' + $name + ';%(AdditionalIncludeDirectories)</AdditionalIncludeDirectories></ClCompile>')
            $lines.Add('    <ClCompile><PreprocessorDefinitions>UNIVERSALDEVKIT_' + $name.ToUpperInvariant() + '_DYNAMIC;%(PreprocessorDefinitions)</PreprocessorDefinitions></ClCompile>')
            $lines.Add('  </ItemDefinitionGroup>')
        }
    }
}
$lines.Add('  <Import Project="UniversalDevKit.Runtime.targets" />')
foreach ($name in $componentNames) {
    $compileSelectors = @($sourceGraphs.Keys | Where-Object { $name -cin $sourceGraphs[$_].RequirementComponents } | Sort-Object)
    $systemSelectors = @($sourceGraphs.Keys | Where-Object { $name -cin $sourceGraphs[$_].SystemLibraryComponents } | Sort-Object)
    if ($compileSelectors.Count) {
        $xml = Get-UdkRequirementItemsXml $name $binaryComponentRegistry[$name].Requirements $true $false
        $lines.Add($xml.Replace('<ItemGroup>', '<ItemGroup Condition="' + (GetSourceCondition $compileSelectors) + '">'))
    }
    if ($systemSelectors.Count) {
        $xml = Get-UdkRequirementItemsXml $name $binaryComponentRegistry[$name].Requirements $false $true
        $lines.Add($xml.Replace('<ItemGroup>', '<ItemGroup Condition="' + (GetSourceCondition $systemSelectors) + '">'))
    }
}
$lines.Add('  <Import Project="UniversalDevKit.Requirements.targets" Condition="''$(__IsUniversalDevKitRequirementsImported)'' != ''true''" />')
$lines.Add('  <Target Name="__UniversalDevKitValidateComponents" BeforeTargets="PrepareForBuild">')
$lines.Add('    <Error Condition="''$(UniversalDevKitComponents)'' == ''''" Text="UniversalDevKitComponents must be specified." />')
$invalidConditions = @($componentNames | ForEach-Object { '''%(__UniversalDevKitComponent.Identity)'' != ''' + $_ + '''' })
$lines.Add('    <Error Condition="' + ($invalidConditions -join ' and ') + '" Text="Unsupported UniversalDevKit component: %(__UniversalDevKitComponent.Identity)" />')
foreach ($rootName in $componentNames) {
    if ($binaryComponentRegistry[$rootName].StateScope -eq 'process') {
        $lines.Add('    <Error Condition="' + (GetSourceCondition @($rootName)) + '" Text="Process-state component requires Dynamic: ' + $rootName + '. Use Connect with a solution." />')
    }
}
# Reject incompatible variants selected by different Shared roots.
foreach ($name in $componentNames) {
    foreach ($firstRoot in @($sourceGraphs.Keys | Sort-Object)) {
        foreach ($secondRoot in @($sourceGraphs.Keys | Sort-Object)) {
            if ($firstRoot -cge $secondRoot) {
                continue
            }
            $firstMode = $sourceGraphs[$firstRoot].ResolvedModes[$name]
            $secondMode = $sourceGraphs[$secondRoot].ResolvedModes[$name]
            if ($firstMode -and $secondMode -and $firstMode -cne $secondMode) {
                $condition = '(' + (GetSourceCondition @($firstRoot)) + ') And (' + (GetSourceCondition @($secondRoot)) + ')'
                $lines.Add('    <Error Condition="' + $condition + '" Text="Conflicting linkage for component: ' + $name + '" />')
            }
        }
    }
}
$lines.Add('  </Target>')
$lines.Add('</Project>')
$relativePath = 'Projects/MsBuild/UniversalDevKit.Sources.targets'
$targetPath = Join-Path $repositoryPath $relativePath
$content = Format-UdkXmlAttributes ($lines -join "`n")
$original = if (Test-Path -LiteralPath $targetPath) {
    [IO.File]::ReadAllText($targetPath)
} else {
    $null
}
if ($null -eq $original -or $original.Replace("`r`n", "`n") -cne $content) {
    $updates.Add([pscustomobject]@{ Path = $targetPath; RelativePath = $relativePath; Content = $content; Original = $original })
}

# Determine all library GUIDs first, including projects not yet created.
$libraryGuids = @{}
$projectTemplate = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Templates/Component.vcxproj.in'))
foreach ($name in $componentNames) {
    foreach ($mode in @('Static', 'Dynamic')) {
        if ($binaryComponentRegistry[$name].Kind -eq 'headerOnly') { continue }
        if ($mode -eq 'Static' -and $binaryComponentRegistry[$name].StateScope -eq 'process') {
            continue
        }
        $relativePath = "Projects/MsBuild/$name/UniversalDevKit.$name.$mode.vcxproj"
        $targetPath = Join-Path $repositoryPath $relativePath
        $configurationType = if ($mode -eq 'Static') {
            'StaticLibrary'
        } else {
            'DynamicLibrary'
        }
        if (Test-Path -LiteralPath $targetPath) {
            # Preserve existing projects and validate required references.
            [xml]$libraryProject = [IO.File]::ReadAllText($targetPath)
            $guidNodes = @($libraryProject.SelectNodes('/*[local-name()="Project"]/*[local-name()="PropertyGroup"]/*[local-name()="ProjectGuid"]'))
            $libraryGuid = [Guid]::Empty
            if ($guidNodes.Count -ne 1 -or -not [Guid]::TryParse($guidNodes[0].InnerText, [ref]$libraryGuid)) {
                throw "Invalid library ProjectGuid: $relativePath"
            }
            $imports = @($libraryProject.SelectNodes('//*[local-name()="Import"]') | ForEach-Object { $_.GetAttribute('Project').Replace('/', '\') })
            foreach ($requiredImport in @("UniversalDevKit.$name.Shared.vcxitems", "UniversalDevKit.$name.Dependencies.props", 'BuildLayout.props', 'Microsoft.Cpp.Default.props', 'Microsoft.Cpp.props', 'Microsoft.Cpp.targets')) {
                if (-not @($imports | Where-Object { ($_ -split '\\')[-1] -ceq $requiredImport }).Count) {
                    throw "Required import $requiredImport is missing from $relativePath. Existing project was not modified."
                }
            }
        }
        else {
            # Derive the GUID deterministically from the Shared project GUID and library variant.
            $hasher = [Security.Cryptography.SHA256]::Create()
            try { $hash = $hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($binaryComponentRegistry[$name].SharedGuid.ToString('D') + ':' + $mode)) }
            finally { $hasher.Dispose() }
            $libraryGuid = [Guid]::new([byte[]]$hash[0..15])
            $definitions = if ($mode -eq 'Dynamic') {
                '      <PreprocessorDefinitions>UNIVERSALDEVKIT_' + $name.ToUpperInvariant() + '_DYNAMIC;UNIVERSALDEVKIT_' + $name.ToUpperInvariant() + '_EXPORTS;%(PreprocessorDefinitions)</PreprocessorDefinitions>'
            } else {
                ''
            }
            $ownGraph = Resolve-UdkLinkageGraph @($name) @{ $name = $mode } $binaryComponentRegistry
            $dependencyRoots = @($binaryComponentRegistry[$name].Dependencies | ForEach-Object { $_.Component })
            $dependencyRequirements = Resolve-UdkLinkageGraph $dependencyRoots $ownGraph.ResolvedModes $binaryComponentRegistry
            $minimumStandard = 17
            foreach ($requiredName in @($name) + @($dependencyRequirements.RequirementComponents)) {
                $minimumStandard = [Math]::Max($minimumStandard, $binaryComponentRegistry[$requiredName].Requirements.CxxStandard)
            }
            $languageStandard = if ($minimumStandard -eq 23) {
                'stdcpplatest'
            } else {
                'stdcpp' + $minimumStandard
            }
            $content = $projectTemplate.Replace('<LanguageStandard>stdcpp17</LanguageStandard>', '<LanguageStandard>' + $languageStandard + '</LanguageStandard>').Replace('@COMPONENT@', $name).Replace('@GUID@', $libraryGuid.ToString().ToUpperInvariant()).Replace('@CONFIGURATION_TYPE@', $configurationType).Replace('@DYNAMIC_DEFINITIONS@', $definitions).TrimEnd([char[]]"`r`n")
            $updates.Add([pscustomobject]@{ Path = $targetPath; RelativePath = $relativePath; Content = $content; Original = $null })
        }
        if (-not $guids.Add($libraryGuid.ToString())) {
            throw "Duplicate library GUID: $relativePath"
        }
        $libraryGuids["$name.$mode"] = '{' + $libraryGuid.ToString().ToUpperInvariant() + '}'
    }
}

# Generate binary references from the same graph; do not merge static archives.
. (Join-Path $PSScriptRoot 'Modules/Module.Udk.Connection/Private/ConnectionPlan.ps1')
foreach ($name in $componentNames) {
    if ($binaryComponentRegistry[$name].Kind -eq 'headerOnly') { continue }
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add('<?xml version="1.0" encoding="utf-8"?>')
    $lines.Add('<!-- Generated by GenerateComponentProjects.ps1. Edit the component registry. -->')
    $lines.Add('<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">')
    foreach ($mode in @('Static', 'Dynamic')) {
        if ($mode -eq 'Static' -and $binaryComponentRegistry[$name].StateScope -eq 'process') {
            continue
        }
        $graph = Resolve-UdkLinkageGraph @($name) @{ $name = $mode } $binaryComponentRegistry
        $roots = @($binaryComponentRegistry[$name].Dependencies | ForEach-Object { $_.Component })
        $dependencyGraph = Resolve-UdkLinkageGraph $roots $graph.ResolvedModes $binaryComponentRegistry
        $configurationType = if ($mode -eq 'Static') {
            'StaticLibrary'
        } else {
            'DynamicLibrary'
        }
        $condition = "'`$(ConfigurationType)' == '$configurationType'"
        $dependencyIncludeRoots = @($dependencyGraph.RequirementComponents | ForEach-Object { '$(MSBuildThisFileDirectory)..\..\..\Includes\' + $_ })
        if ($dependencyIncludeRoots.Count) {
            $lines.Add('  <ItemDefinitionGroup Condition="' + $condition + '"><ClCompile><AdditionalIncludeDirectories>' + ($dependencyIncludeRoots -join ';') + ';%(AdditionalIncludeDirectories)</AdditionalIncludeDirectories></ClCompile></ItemDefinitionGroup>')
        }
        foreach ($dependencyName in $dependencyGraph.ResolvedComponents) {
            $compile = $dependencyName -cin $dependencyGraph.RequirementComponents
            $system = $mode -eq 'Dynamic' -and $dependencyName -cin $dependencyGraph.SystemLibraryComponents
            $xml = Get-UdkRequirementItemsXml $dependencyName $binaryComponentRegistry[$dependencyName].Requirements $compile $system
            $lines.Add($xml.Replace('<ItemGroup>', '<ItemGroup Condition="' + $condition + '">'))
        }
        $lines.Add('  <ItemGroup Condition="' + $condition + '">')
        foreach ($dependencyName in @($graph.ResolvedComponents | Where-Object { $_ -ne $name })) {
            if ($binaryComponentRegistry[$dependencyName].Kind -eq 'headerOnly') { continue }
            $dependencyMode = $graph.ResolvedModes[$dependencyName]
            $dependencyGuid = $libraryGuids["$dependencyName.$dependencyMode"]
            $link = if ($mode -eq 'Dynamic' -and $dependencyName -cin $dependencyGraph.LinkComponents) {
                'true'
            } else {
                'false'
            }
            $lines.Add('    <ProjectReference Include="$(MSBuildThisFileDirectory)..\' + $dependencyName + '\UniversalDevKit.' + $dependencyName + '.' + $dependencyMode + '.vcxproj">')
            $lines.Add('      <Project>' + $dependencyGuid + '</Project>')
            $lines.Add('      <LinkLibraryDependencies>' + $link + '</LinkLibraryDependencies>')
            $lines.Add('    </ProjectReference>')
        }
        $lines.Add('  </ItemGroup>')
        $definitions = @($dependencyGraph.DefinitionComponents | ForEach-Object { 'UNIVERSALDEVKIT_' + $_.ToUpperInvariant() + '_DYNAMIC' })
        if ($definitions.Count) {
            $lines.Add('  <ItemDefinitionGroup Condition="' + $condition + '">')
            $lines.Add('    <ClCompile><PreprocessorDefinitions>' + ($definitions -join ';') + ';%(PreprocessorDefinitions)</PreprocessorDefinitions></ClCompile>')
            $lines.Add('  </ItemDefinitionGroup>')
        }
    }
    $lines.Add('</Project>')
    $relativePath = "Projects/MsBuild/$name/UniversalDevKit.$name.Dependencies.props"
    $targetPath = Join-Path $repositoryPath $relativePath
    $content = Format-UdkXmlAttributes ($lines -join "`n")
    $original = if (Test-Path -LiteralPath $targetPath) {
        [IO.File]::ReadAllText($targetPath)
    } else {
        $null
    }
    if ($null -eq $original -or $original.Replace("`r`n", "`n") -cne $content) {
        $updates.Add([pscustomobject]@{ Path = $targetPath; RelativePath = $relativePath; Content = $content; Original = $original })
    }
}

# Allow inspection of the generation plan without writing files.
# Add new components to the solution while preserving its tree and manual settings.
$solutionPath = Join-Path $repositoryPath 'UniversalDevKit.sln'
if (Test-Path -LiteralPath $solutionPath) {
    $solutionOriginal = [IO.File]::ReadAllText($solutionPath)
    $solutionContent = $solutionOriginal
    $solutionNewline = if ($solutionOriginal.Contains("`r`n")) {
        "`r`n"
    } else {
        "`n"
    }
    foreach ($name in $componentNames) {
        foreach ($mode in @('Shared', 'Static', 'Dynamic')) {
            if ($mode -ne 'Shared' -and $binaryComponentRegistry[$name].Kind -eq 'headerOnly') { continue }
            if ($mode -ne 'Dynamic' -and $binaryComponentRegistry[$name].StateScope -eq 'process') {
                continue
            }
            $extension = if ($mode -eq 'Shared') {
                'vcxitems'
            } else {
                'vcxproj'
            }
            $projectPath = "Projects\MsBuild\$name\UniversalDevKit.$name.$mode.$extension"
            if ($solutionContent.Contains('"' + $projectPath + '"')) {
                continue
            }
            $projectGuid = if ($mode -eq 'Shared') {
                '{' + $binaryComponentRegistry[$name].SharedGuid.ToString().ToUpperInvariant() + '}'
            } else {
                $libraryGuids["$name.$mode"]
            }
            $projectType = if ($mode -eq 'Shared') {
                '{D954291E-2A0B-460D-934E-DC6B0785DB48}'
            } else {
                '{8BC9CEB8-8B4A-11D0-8D11-00A0C91BC942}'
            }
            $entry = 'Project("' + $projectType + '") = "UniversalDevKit.' + $name + '.' + $mode + '", "' + $projectPath + '", "' + $projectGuid + '"' + $solutionNewline + 'EndProject' + $solutionNewline
            $solutionContent = [regex]::Replace($solutionContent, '(?m)^Global\r?$', { param($match) $entry + $match.Value }, 1)
            if ($mode -ne 'Shared') {
                $configurationLines = ''
                foreach ($configuration in @('Debug', 'Release')) {
                    $configurationLines += "`t`t$projectGuid.$configuration|x64.ActiveCfg = $configuration|x64$solutionNewline"
                    $configurationLines += "`t`t$projectGuid.$configuration|x64.Build.0 = $configuration|x64$solutionNewline"
                }
                $solutionContent = [regex]::Replace($solutionContent, '(?m)^(\s*GlobalSection\(ProjectConfigurationPlatforms\) = postSolution\r?\n)', { param($match) $match.Value + $configurationLines }, 1)
            }
        }
    }
    if ($solutionContent -cne $solutionOriginal) {
        $updates.Add([pscustomobject]@{ Path = $solutionPath; RelativePath = 'UniversalDevKit.sln'; Content = $solutionContent.TrimEnd([char[]]"`r`n"); Original = $solutionOriginal })
    }
}

# Generate export headers for every component, including test registries.
function AddGeneratedMetadata([string]$RelativePath, [string]$Content) {
    $path = Join-Path $repositoryPath $RelativePath
    $content = $Content.TrimEnd([char[]]"`r`n")
    $original = if (Test-Path -LiteralPath $path) { [IO.File]::ReadAllText($path) } else { $null }
    if ($original -cne $content) {
        $updates.Add([pscustomobject]@{ Path = $path; RelativePath = $RelativePath; Content = $content; Original = $original })
    }
}
$exportTemplate = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Templates/Export.h.in'))
$componentExportTemplate = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Templates/ComponentExport.h.in'))
AddGeneratedMetadata 'Includes/Core/UniversalDevKit/Export.h' $exportTemplate
foreach ($name in $componentNames) {
    AddGeneratedMetadata "Includes/$name/UniversalDevKit/$name/Export.h" ($componentExportTemplate.Replace('@COMPONENT@', $name.ToUpperInvariant()))
}
$versionPath = Join-Path $repositoryPath 'Version.json'
if (Test-Path -LiteralPath $versionPath) {
    $version = Get-Content -LiteralPath $versionPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($version.version -notmatch '^\d+\.\d+\.\d+$' -or [string]$version.abiVersion -notmatch '^\d+$') { throw 'Invalid Version.json' }
    AddGeneratedMetadata 'Includes/Core/UniversalDevKit/Version.h' ("// Generated by GenerateComponentProjects.ps1. Edit Version.json.`n#pragma once`n`n#define UNIVERSALDEVKIT_VERSION `"$($version.version)`"`n#define UNIVERSALDEVKIT_ABI_VERSION $($version.abiVersion)")
    $versionLines = @(
        '<?xml version="1.0" encoding="utf-8"?>'
        '<!-- Generated by GenerateComponentProjects.ps1. Edit Version.json. -->'
        '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">'
        '  <PropertyGroup>'
        ('    <UniversalDevKitVersion>' + $version.version + '</UniversalDevKitVersion>')
        ('    <UniversalDevKitAbiVersion>' + $version.abiVersion + '</UniversalDevKitAbiVersion>')
        '  </PropertyGroup>'
        '</Project>'
    )
    AddGeneratedMetadata 'Projects/MsBuild/UniversalDevKit.Version.props' ($versionLines -join "`n")
}

if ($PassThru) {
    return $updates.ToArray()
}
if ($Check) {
    if ($updates.Count) {
        throw ('Generated projects are out of date: ' + (($updates | ForEach-Object { $_.RelativePath }) -join ', '))
    }
    Write-Output 'Component projects are up to date.'
    & (Join-Path $PSScriptRoot 'UpdateProjectFilters.ps1') -RepositoryRoot $repositoryPath -Check
    return
}
if (-not $updates.Count) {
    Write-Output 'Component projects are up to date.'
}
# Write only after validating all included component descriptions.
foreach ($update in $updates) {
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($update.Path))
    [IO.File]::WriteAllText($update.Path, $update.Content, [Text.UTF8Encoding]::new($false))
    Write-Output ('Updated: ' + $update.RelativePath)
}

# Update filters even when projects are unchanged; only .filters may be stale.
& (Join-Path $PSScriptRoot 'UpdateProjectFilters.ps1') -RepositoryRoot $repositoryPath