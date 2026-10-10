param(
    [string]$RepositoryRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [switch]$Check
)

$ErrorActionPreference = 'Stop'
$repositoryPath = [IO.Path]::GetFullPath($RepositoryRoot)
$manifest = Get-Content -LiteralPath (Join-Path $repositoryPath 'Components.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1) { throw 'Unsupported Components.json schemaVersion.' }
foreach ($field in $manifest.PSObject.Properties.Name) {
    if ($field -notin @('schemaVersion', 'includes')) { throw "Unsupported manifest field: $field" }
}
if ($manifest.includes -isnot [Array] -or -not $manifest.includes.Count) {
    throw 'Components.json must contain a nonempty includes array.'
}
$updates = [Collections.Generic.List[object]]::new()
$guids = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$includePaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$componentGraph = @{}

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
    if ($null -eq $Settings) { return }
    if ($Settings -isnot [pscustomobject]) { throw 'filters must be an object.' }
    foreach ($field in $Settings.PSObject.Properties.Name) {
        if ($field -notin @('roots', 'files')) { throw "Unsupported filters field: $field" }
    }
    if ($Settings.PSObject.Properties['roots']) {
        if ($Settings.roots -isnot [Array]) { throw 'filters.roots must be an array.' }
        $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($rule in $Settings.roots) {
            if ($rule -isnot [pscustomobject]) { throw 'Filter root must be an object.' }
            foreach ($field in $rule.PSObject.Properties.Name) {
                if ($field -notin @('path', 'filter')) { throw "Unsupported filter root field: $field" }
            }
            ValidateFilterPath $rule.path 'roots.path'
            ValidateFilterPath $rule.filter 'roots.filter'
            if ($rule.path -eq '' -or -not $seen.Add($rule.path)) { throw "Empty or duplicate filter root: $($rule.path)" }
        }
    }
    if ($Settings.PSObject.Properties['files']) {
        if ($Settings.files -isnot [pscustomobject]) { throw 'filters.files must be an object.' }
        $knownFiles = @($Component.headers) + @($Component.sources)
        foreach ($entry in $Settings.files.PSObject.Properties) {
            if ($entry.Name -cnotin $knownFiles) { throw "Unknown filters.files entry: $($entry.Name)" }
            ValidateFilterPath $entry.Value $entry.Name
        }
    }
}

function GetComponentFilter([string]$Path, $Settings) {
    # Исключение файла имеет приоритет; пустая строка помещает файл в корень проекта.
    if ($null -ne $Settings -and $null -ne $Settings.files) {
        $entry = $Settings.files.PSObject.Properties[$Path]
        if ($entry) { return $entry.Value.Replace('/', '\') }
    }
    $mapped = $Path
    if ($null -ne $Settings) {
        $best = $null
        foreach ($rule in $Settings.roots) {
            if ($Path.StartsWith($rule.path + '/', [StringComparison]::Ordinal) -and
                ($null -eq $best -or $rule.path.Length -gt $best.path.Length)) { $best = $rule }
        }
        if ($null -ne $best) {
            $mapped = $Path.Substring($best.path.Length + 1)
            if ($best.filter -ne '') { $mapped = $best.filter + '/' + $mapped }
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
    if (-not $includePaths.Add($includePath)) { throw "Duplicate component include: $includePath" }
    $component = Get-Content -LiteralPath (Join-Path $repositoryPath $includePath) -Raw -Encoding UTF8 | ConvertFrom-Json
    $name = $component.name
    if ($name -isnot [string]) { throw "Component name must be a string: $includePath" }
    if ($name -notmatch '^[A-Z][A-Za-z0-9]*$') { throw "Invalid component name: $name" }
    if (-not $names.Add($name)) { throw "Duplicate component name: $name" }
    # Не игнорируем будущие поля: для зависимостей и платформ потребуется расширение генератора.
    foreach ($field in $component.PSObject.Properties.Name) {
        if ($field -notin @('name', 'msbuildGuid', 'headers', 'sources', 'filters', 'dependencies')) { throw "Unsupported field ${name}: $field" }
    }
    $guid = [Guid]::Empty
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
        if ($component.dependencies -isnot [Array]) { throw "${name}.dependencies must be an array." }
        foreach ($dependency in $component.dependencies) {
            if ($dependency -isnot [pscustomobject]) { throw "Invalid dependency in $name" }
            foreach ($field in $dependency.PSObject.Properties.Name) {
                if ($field -notin @('component', 'visibility', 'linkage')) { throw "Unsupported dependency field: $field" }
            }
            if ($dependency.component -isnot [string] -or $dependency.component -notmatch '^[A-Z][A-Za-z0-9]*$') {
                throw "Invalid dependency component in $name"
            }
            if ($dependency.visibility -cnotin @('private', 'public') -or $dependency.linkage -cnotin @('same', 'static')) {
                throw "Invalid dependency visibility or linkage in $name"
            }
            if ($dependencies.Contains($dependency.component)) { throw "Duplicate dependency in ${name}: $($dependency.component)" }
            $dependencies.Add($dependency.component)
        }
    }
    $componentGraph[$name] = $dependencies.ToArray()
    if ($component.PSObject.Properties['filters'] -and $null -eq $component.filters) {
        throw "${name}.filters must be an object."
    }
    ValidateFilterSettings $component.filters $component
    $files = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $objects = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add('<?xml version="1.0" encoding="utf-8"?>')
    $lines.Add('<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">')
    $lines.Add('  <!-- Сформировано из Components.json; изменяйте реестр и запускайте GenerateComponentProjects. -->')
    $lines.Add('  <PropertyGroup Label="Globals">')
    $lines.Add('    <HasSharedItems>true</HasSharedItems>')
    $lines.Add('    <ItemsProjectGuid>{' + $guid.ToString().ToUpperInvariant() + '}</ItemsProjectGuid>')
    $lines.Add('  </PropertyGroup>')
    $lines.Add('  <Import Project="$(MSBuildThisFileDirectory)..\UniversalDevKit.props" Condition="''$(__IsUniversalDevKitPublicPropsImported)'' != ''true''" />')
    $lines.Add('  <ItemGroup>')
    foreach ($path in $component.headers) {
        if ($path -isnot [string]) { throw "${name}.headers must contain strings." }
        ValidateFile $path "Includes/UniversalDevKit/$name/"
        if (-not $files.Add($path)) { throw "Duplicate component file: $path" }
        $include = EscapeXml ('$' + '(MSBuildThisFileDirectory)..\..\..\' + $path.Replace('/', '\'))
        $lines.Add('    <ClInclude Include="' + $include + '">')
        $lines.Add('      <__UniversalDevKitFilter>' + (EscapeXml (GetComponentFilter $path $component.filters)) + '</__UniversalDevKitFilter>')
        $lines.Add('    </ClInclude>')
    }
    foreach ($path in $component.sources) {
        if ($path -isnot [string]) { throw "${name}.sources must contain strings." }
        ValidateFile $path "Sources/$name/"
        if (-not $files.Add($path)) { throw "Duplicate component file: $path" }
        if ([IO.Path]::GetExtension($path) -cne '.cpp') { throw "Expected .cpp source: $path" }
        $relative = $path.Substring("Sources/$name/".Length)
        $object = [IO.Path]::ChangeExtension($relative, '.obj').Replace('/', '\')
        if (-not $objects.Add($object)) { throw "Duplicate object path: $path" }
        $include = EscapeXml ('$' + '(MSBuildThisFileDirectory)..\..\..\' + $path.Replace('/', '\'))
        $lines.Add('    <ClCompile Include="' + $include + '">')
        $lines.Add('      <__UniversalDevKitFilter>' + (EscapeXml (GetComponentFilter $path $component.filters)) + '</__UniversalDevKitFilter>')
        $lines.Add('      <PrecompiledHeader>NotUsing</PrecompiledHeader>')
        $lines.Add('      <ObjectFileName>$(IntDir)UniversalDevKit\' + $name + '\' + (EscapeXml $object) + '</ObjectFileName>')
        $lines.Add('    </ClCompile>')
    }
    $lines.Add('  </ItemGroup>')
    $lines.Add('</Project>')
    $relativePath = "Projects/MsBuild/$name/UniversalDevKit.$name.Shared.vcxitems"
    $targetPath = Join-Path $repositoryPath $relativePath
    $content = $lines -join "`n"
    $original = if (Test-Path -LiteralPath $targetPath) { [IO.File]::ReadAllText($targetPath) } else { $null }
    # Различие CRLF/LF само по себе не требует перезаписи.
    if ($null -eq $original -or $original.Replace("`r`n", "`n") -cne $content) {
        $updates.Add([pscustomobject]@{ Path = $targetPath; RelativePath = $relativePath; Content = $content; Original = $original })
    }
}

# Замыкание зависимостей вычисляется до записи; цикл или неизвестное имя останавливают генерацию.
function GetDependencyClosure([string]$Name, [string[]]$Stack) {
    if ($Name -cin $Stack) { throw ('Component dependency cycle: ' + (($Stack + $Name) -join ' -> ')) }
    if ($Name -cnotin @($componentGraph.Keys)) { throw "Unknown dependency component: $Name" }
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
$lines.Add('       из Components.json и включённых описаний в Projects/Components/.')
$lines.Add('       Не редактируйте его вручную: изменения будут заменены при следующей генерации.')
$lines.Add('       Для обновления измените JSON и запустите Scripts/GenerateComponentProjects.cmd.')
$lines.Add('')
$lines.Add('       Connect добавляет в проект потребителя выбор UniversalDevKitComponents и импорт этого файла.')
$lines.Add('       При вычислении MSBuild подключаются заголовки и исходники выбранных компонентов')
$lines.Add('       вместе со всеми транзитивными зависимостями; каждый Shared-проект импортируется один раз.')
$lines.Add('       Исходники не копируются и компилируются с настройками проекта потребителя.')
$lines.Add('       Каталог доступных компонентов используется меню Connect, а перед сборкой проверяется выбор. -->')
$lines.Add('<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">')
$lines.Add('  <Import Project="UniversalDevKit.props" Condition="''$(__IsUniversalDevKitPublicPropsImported)'' != ''true''" />')
$lines.Add('  <ItemGroup>')
$lines.Add('    <__UniversalDevKitAvailableComponent Include="' + ($componentNames -join ';') + '" />')
$lines.Add('    <__UniversalDevKitComponent Include="$(UniversalDevKitComponents)" />')
$lines.Add('  </ItemGroup>')
$lines.Add('  <PropertyGroup>')
foreach ($name in $componentNames) {
    $selectors = @($componentNames | Where-Object { $name -cin $closures[$_] })
    $conditions = @($selectors | ForEach-Object {
        '$([System.String]::Copy('';$(UniversalDevKitComponents);'').Contains('';' + $_ + ';''))'
    })
    $lines.Add('    <__HasUniversalDevKit' + $name + '>false</__HasUniversalDevKit' + $name + '>')
    $lines.Add('    <__HasUniversalDevKit' + $name + ' Condition="' + ($conditions -join ' Or ') + '">true</__HasUniversalDevKit' + $name + '>')
}
$lines.Add('  </PropertyGroup>')
foreach ($name in $componentNames) {
    $lines.Add('  <Import Project="' + $name + '\UniversalDevKit.' + $name + '.Shared.vcxitems" Condition="' +
        '''$(__HasUniversalDevKit' + $name + ')'' == ''true''" Label="Shared" />')
}
$lines.Add('  <Target Name="__UniversalDevKitValidateComponents" BeforeTargets="PrepareForBuild">')
$lines.Add('    <Error Condition="''$(UniversalDevKitComponents)'' == ''''" Text="UniversalDevKitComponents must be specified." />')
$invalidConditions = @($componentNames | ForEach-Object { '''%(__UniversalDevKitComponent.Identity)'' != ''' + $_ + '''' })
$lines.Add('    <Error Condition="' + ($invalidConditions -join ' and ') + '" Text="Unsupported UniversalDevKit component: %(__UniversalDevKitComponent.Identity)" />')
$lines.Add('  </Target>')
$lines.Add('</Project>')
$relativePath = 'Projects/MsBuild/UniversalDevKit.Sources.targets'
$targetPath = Join-Path $repositoryPath $relativePath
$content = $lines -join "`n"
$original = if (Test-Path -LiteralPath $targetPath) { [IO.File]::ReadAllText($targetPath) } else { $null }
if ($null -eq $original -or $original.Replace("`r`n", "`n") -cne $content) {
    $updates.Add([pscustomobject]@{ Path = $targetPath; RelativePath = $relativePath; Content = $content; Original = $original })
}

if ($Check) {
    if ($updates.Count) { throw ('Generated projects are out of date: ' + (($updates | ForEach-Object { $_.RelativePath }) -join ', ')) }
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