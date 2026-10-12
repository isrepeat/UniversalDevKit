param(
    [string]$RepositoryRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [switch]$Check,
    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'FormatXmlAttributes.ps1')
$repositoryPath = [IO.Path]::GetFullPath($RepositoryRoot)
$manifest = Get-Content -LiteralPath (Join-Path $repositoryPath 'Components.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1) {
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
    # Только явные пути внутри компонента: без wildcard, макросов и выхода из репозитория.
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
    # Исключение файла имеет приоритет; пустая строка помещает файл в корень проекта.
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
    # includes отсчитываются от корневого Components.json; вложенные include не поддерживаются.
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
    # Не игнорируем будущие поля: для зависимостей и платформ потребуется расширение генератора.
    foreach ($field in $component.PSObject.Properties.Name) {
        if ($field -notin @('name', 'msbuildGuid', 'headers', 'sources', 'filters', 'dependencies', 'supportedPlatforms', 'platformSources', 'stateScope')) {
            throw "Unsupported field ${name}: $field"
        }
    }
    $guid = [Guid]::Empty
    if ($component.PSObject.Properties['stateScope'] -and $component.stateScope -cnotin @('module', 'process')) {
        throw "Invalid stateScope for component: $name"
    }
    if (-not [Guid]::TryParse([string]$component.msbuildGuid, [ref]$guid) -or -not $guids.Add($guid.ToString())) {
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
        StateScope = $component.stateScope
        Dependencies = @($component.dependencies | ForEach-Object {
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
    ValidateFilterSettings $component.filters $component
    $files = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $objects = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add('<?xml version="1.0" encoding="utf-8"?>')
    $lines.Add('<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">')
    $lines.Add('  <!-- Сформировано из Components.json; изменяйте реестр компонентов и запускайте GenerateComponentProjects. -->')
    $lines.Add('  <PropertyGroup Label="Globals">')
    $lines.Add('    <HasSharedItems>true</HasSharedItems>')
    $lines.Add('    <ItemsProjectGuid>{' + $guid.ToString().ToUpperInvariant() + '}</ItemsProjectGuid>')
    $lines.Add('  </PropertyGroup>')
    $lines.Add('  <Import Project="$(MSBuildThisFileDirectory)..\UniversalDevKit.props" Condition="''$(__IsUniversalDevKitPublicPropsImported)'' != ''true''" />')
    $lines.Add('  <ItemGroup>')
    foreach ($path in $component.headers) {
        if ($path -isnot [string]) {
            throw "${name}.headers must contain strings."
        }
        ValidateFile $path "Includes/UniversalDevKit/$name/"
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
        # Список файлов нужен самой DLL, но запрещён для компиляции внутри consumer.
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
    $lines.Add('</Project>')
    $relativePath = "Projects/MsBuild/$name/UniversalDevKit.$name.Shared.vcxitems"
    $targetPath = Join-Path $repositoryPath $relativePath
    $content = $lines -join "`n"
    $original = if (Test-Path -LiteralPath $targetPath) {
        [IO.File]::ReadAllText($targetPath)
    } else {
        $null
    }
    # Различие CRLF/LF само по себе не требует перезаписи.
    if ($null -eq $original -or $original.Replace("`r`n", "`n") -cne $content) {
        $updates.Add([pscustomobject]@{ Path = $targetPath; RelativePath = $relativePath; Content = $content; Original = $original })
    }
}

# Замыкание зависимостей вычисляется до записи; цикл или неизвестное имя останавливают генерацию.
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

$lines = [Collections.Generic.List[string]]::new()
$lines.Add('<?xml version="1.0" encoding="utf-8"?>')
$lines.Add('<!-- Этот файл полностью формируется Scripts/PowerShell/GenerateComponentProjects.ps1')
$lines.Add('     из Components.json и включённых описаний в Projects/Components/.')
$lines.Add('     Не редактируйте его вручную: изменения будут заменены при следующей генерации.')
$lines.Add('     Для обновления измените JSON и запустите Scripts/GenerateComponentProjects.cmd.')
$lines.Add('')
$lines.Add('     Connect добавляет в проект потребителя выбор UniversalDevKitComponents и импорт этого файла.')
$lines.Add('     При вычислении MSBuild подключаются заголовки и исходники выбранных компонентов')
$lines.Add('     вместе со всеми транзитивными зависимостями; каждый Shared-проект импортируется один раз.')
$lines.Add('     Исходники не копируются и компилируются с настройками проекта потребителя.')
$lines.Add('     Реестр компонентов используется меню Connect, а перед сборкой проверяется выбор. -->')
$lines.Add('<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">')
$lines.Add('  <Import Project="UniversalDevKit.props" Condition="''$(__IsUniversalDevKitPublicPropsImported)'' != ''true''" />')
$lines.Add('  <ItemGroup>')
$lines.Add('    <__UniversalDevKitAvailableComponent Include="' + ($componentNames -join ';') + '" />')
$lines.Add('    <__UniversalDevKitComponent Include="$(UniversalDevKitComponents)" />')
$lines.Add('  </ItemGroup>')
# Для ProjectOnly раскрываем Shared-граф, сохраняя явно динамические зависимости.
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
            $lines.Add('    <ClCompile><PreprocessorDefinitions>UNIVERSALDEVKIT_' + $name.ToUpperInvariant() + '_DYNAMIC;%(PreprocessorDefinitions)</PreprocessorDefinitions></ClCompile>')
            $lines.Add('  </ItemDefinitionGroup>')
        }
    }
}
$lines.Add('  <Import Project="UniversalDevKit.Runtime.targets" />')
$lines.Add('  <Target Name="__UniversalDevKitValidateComponents" BeforeTargets="PrepareForBuild">')
$lines.Add('    <Error Condition="''$(UniversalDevKitComponents)'' == ''''" Text="UniversalDevKitComponents must be specified." />')
$invalidConditions = @($componentNames | ForEach-Object { '''%(__UniversalDevKitComponent.Identity)'' != ''' + $_ + '''' })
$lines.Add('    <Error Condition="' + ($invalidConditions -join ' and ') + '" Text="Unsupported UniversalDevKit component: %(__UniversalDevKitComponent.Identity)" />')
foreach ($rootName in $componentNames) {
    if ($binaryComponentRegistry[$rootName].StateScope -eq 'process') {
        $lines.Add('    <Error Condition="' + (GetSourceCondition @($rootName)) + '" Text="Process-state component requires Dynamic: ' + $rootName + '. Use Connect with a solution." />')
    }
}
# Отклоняем несовместимые варианты, выбранные разными Shared-корнями.
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

# Сначала определяем GUID всех библиотек, включая ещё не созданные проекты.
$libraryGuids = @{}
$projectTemplate = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Templates/Component.vcxproj.in'))
foreach ($name in $componentNames) {
    foreach ($mode in @('Static', 'Dynamic')) {
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
            # Существующие проекты не переписываем; проверяем обязательные связи.
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
            # GUID детерминирован по GUID Shared-проекта и варианту библиотеки.
            $hasher = [Security.Cryptography.SHA256]::Create()
            try { $hash = $hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($binaryComponentRegistry[$name].SharedGuid.ToString('D') + ':' + $mode)) }
            finally { $hasher.Dispose() }
            $libraryGuid = [Guid]::new([byte[]]$hash[0..15])
            $definitions = if ($mode -eq 'Dynamic') {
                '      <PreprocessorDefinitions>UNIVERSALDEVKIT_' + $name.ToUpperInvariant() + '_DYNAMIC;UNIVERSALDEVKIT_' + $name.ToUpperInvariant() + '_EXPORTS;%(PreprocessorDefinitions)</PreprocessorDefinitions>'
            } else {
                ''
            }
            $content = $projectTemplate.Replace('@COMPONENT@', $name).Replace('@GUID@', $libraryGuid.ToString().ToUpperInvariant()).Replace('@CONFIGURATION_TYPE@', $configurationType).Replace('@DYNAMIC_DEFINITIONS@', $definitions).TrimEnd([char[]]"`r`n")
            $updates.Add([pscustomobject]@{ Path = $targetPath; RelativePath = $relativePath; Content = $content; Original = $null })
        }
        if (-not $guids.Add($libraryGuid.ToString())) {
            throw "Duplicate library GUID: $relativePath"
        }
        $libraryGuids["$name.$mode"] = '{' + $libraryGuid.ToString().ToUpperInvariant() + '}'
    }
}

# Бинарные связи формируются из того же графа; статические архивы не объединяем.
. (Join-Path $PSScriptRoot 'Modules/Module.Udk.Connection/Private/ConnectionPlan.ps1')
foreach ($name in $componentNames) {
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add('<?xml version="1.0" encoding="utf-8"?>')
    $lines.Add('<!-- Сформировано из Components.json; не редактируйте вручную. -->')
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
        $lines.Add('  <ItemGroup Condition="' + $condition + '">')
        foreach ($dependencyName in @($graph.ResolvedComponents | Where-Object { $_ -ne $name })) {
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

# Позволяет получить план генерации без записи файлов.
# Новые компоненты добавляем в solution, сохраняя существующее дерево и ручные настройки.
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
# Записываем только после проверки всех включённых описаний компонентов.
foreach ($update in $updates) {
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($update.Path))
    [IO.File]::WriteAllText($update.Path, $update.Content, [Text.UTF8Encoding]::new($false))
    Write-Output ('Updated: ' + $update.RelativePath)
}

# Фильтры обновляем и при неизменившихся проектах: устареть может только .filters.
& (Join-Path $PSScriptRoot 'UpdateProjectFilters.ps1') -RepositoryRoot $repositoryPath