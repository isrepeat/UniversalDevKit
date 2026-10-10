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
        if ($field -notin @('name', 'msbuildGuid', 'headers', 'sources')) { throw "Unsupported field ${name}: $field" }
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
    $files = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $objects = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add('<?xml version="1.0" encoding="utf-8"?>')
    $lines.Add('<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">')
    $lines.Add('  <!-- Сформировано из Components.json; изменяйте реестр и запускайте GenerateComponentProjects. -->')
    $lines.Add('  <PropertyGroup Label="Globals">')
    $lines.Add('    <HasSharedItems>true</HasSharedItems>')
    $lines.Add('    <ItemsProjectGuid>{' + $guid.ToString().ToUpperInvariant() + '}</ItemsProjectGuid>')
    $lines.Add('    <UniversalDevKitFilterRoots>Includes\UniversalDevKit\' + $name + ';Sources\' + $name + '</UniversalDevKitFilterRoots>')
    $lines.Add('  </PropertyGroup>')
    $lines.Add('  <Import Project="$(MSBuildThisFileDirectory)..\UniversalDevKit.props" Condition="''$(__IsUniversalDevKitPublicPropsImported)'' != ''true''" />')
    $lines.Add('  <ItemGroup>')
    foreach ($path in $component.headers) {
        if ($path -isnot [string]) { throw "${name}.headers must contain strings." }
        ValidateFile $path "Includes/UniversalDevKit/$name/"
        if (-not $files.Add($path)) { throw "Duplicate component file: $path" }
        $include = EscapeXml ('$' + '(MSBuildThisFileDirectory)..\..\..\' + $path.Replace('/', '\'))
        $lines.Add('    <ClInclude Include="' + $include + '" />')
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

if ($Check) {
    if ($updates.Count) { throw ('Generated projects are out of date: ' + (($updates | ForEach-Object { $_.RelativePath }) -join ', ')) }
    Write-Output 'Component projects are up to date.'
    return
}
if (-not $updates.Count) {
    Write-Output 'Component projects are up to date.'
    return
}
# Записываем только после проверки всех включённых описаний компонентов.
foreach ($update in $updates) {
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($update.Path))
    [IO.File]::WriteAllText($update.Path, $update.Content, [Text.UTF8Encoding]::new($false))
    Write-Output ('Updated: ' + $update.RelativePath)
}