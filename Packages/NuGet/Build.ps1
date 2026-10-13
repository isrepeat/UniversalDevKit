param(
    [string]$CMake,
    [string]$NuGet = 'nuget.exe',
    [Parameter(Mandatory = $true)][string]$LicenseFile,
    [string]$OutputDirectory,
    [string[]]$Components,
    [string]$Generator = 'Visual Studio 18 2026',
    [string]$RepositoryPath = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
)

$ErrorActionPreference = 'Stop'

# 1. Находим инструменты и отдельный каталог выпуска; версию читаем из общего источника.
$repository = (Resolve-Path -LiteralPath $RepositoryPath).Path
if (-not $CMake) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    $CMake = @(& $vswhere -latest -products '*' -find 'Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe')[0]
}
if (-not $CMake -or -not (Get-Command $CMake -ErrorAction SilentlyContinue)) { throw 'CMake is required.' }
$license = (Resolve-Path -LiteralPath $LicenseFile).Path
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repository ('!artifacts/packages/nuget/' + [Guid]::NewGuid().ToString('N')) }
$output = [IO.Path]::GetFullPath($OutputDirectory)
[void][IO.Directory]::CreateDirectory($output)
$version = (Get-Content (Join-Path $repository 'Version.json') -Raw | ConvertFrom-Json).version

# 2. Проверяем реестр и добавляем зависимости выбранных компонентов в состав выпуска.
$connection = Join-Path $repository 'Scripts/PowerShell/Modules/Module.Udk.Connection/Private'
. (Join-Path $connection 'Requirements.ps1')
. (Join-Path $connection 'ComponentRegistry.ps1')
. (Join-Path $connection 'ConnectionPlan.ps1')
$registry = Get-UdkComponentRegistry $repository
if (-not $Components) { $Components = @($registry.Keys | Sort-Object) }
$selected = @(Resolve-UdkComponents $Components $registry)
$hasBinaries = @($selected | Where-Object { $registry[$_].Kind -ne 'headerOnly' }).Count -gt 0

# 3. Для каждого допустимого режима заранее получаем линковку, публичные требования и DLL.
# Один расчёт используется Connect и пакетами; имена поступают из реестра.
$graphs = @{}
foreach ($name in $selected) {
    $modes = if ($registry[$name].Kind -eq 'headerOnly') { @('Shared') } elseif ($registry[$name].StateScope -eq 'process') { @('Dynamic') } else { @('Static', 'Dynamic') }
    foreach ($mode in $modes) { $graphs["$name.$mode"] = Resolve-UdkLinkageGraph @($name) @{ $name = $mode } $registry }
}

# Возвращаем выражения MSBuild: пути вычисляются у consumer после restore, а не на машине выпуска.
function PackageRoot([string]$Name) { return '$(__UniversalDevKit' + $Name + 'PackageRoot)' }
function RootCondition([string]$Name, [string]$Mode) {
    # Зависимость доставляется NuGet, но становится корнем только при явном выборе consumer.
    return "`$([System.String]::Copy(';`$(UniversalDevKitComponents);').Contains(';$Name;')) and '`$(UniversalDevKit${Name}Linkage)' == '$Mode'"
}
function GetEntry($Record, [string]$Name, [string]$Mode) {
    # Имена файлов берём из фактической сборки, включая Debug-суффиксы.
    $entries = @($Record.Metadata.components | Where-Object { $_.name -ceq $Name -and $_.variant -ceq $Mode })
    if ($entries.Count -ne 1) { throw "Missing packaged variant: $Name.$Mode" }
    return $entries[0]
}
function GetDll($Record, [string]$Name) {
    # В Windows импортная .lib и DLL имеют общий stem; неоднозначное соответствие отклоняем.
    $entry = GetEntry $Record $Name 'Dynamic'
    $stem = [IO.Path]::GetFileNameWithoutExtension($entry.linkFile)
    $files = @($Record.Metadata.runtimeFiles | Where-Object { [IO.Path]::GetFileNameWithoutExtension($_) -ceq $stem })
    if ($files.Count -ne 1) { throw "Runtime file missing or ambiguous: $Name" }
    return $files[0]
}

function WriteGenerated([string]$Path, [string]$Content) {
    # Записываем только генерируемые артефакты staging: UTF-8 без BOM и конечных CR/LF.
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    [IO.File]::WriteAllText($Path, $Content.TrimEnd([char[]]"`r`n"), [Text.UTF8Encoding]::new($false))
}
function RunCMake([string[]]$Arguments) {
    & $CMake @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'CMake packaging build failed.' }
}

# 4. Собираем MD/MT в отдельных prefix; Debug/Release одного CRT устанавливаем вместе.
$records = @()
foreach ($runtime in @('Dynamic', 'Static')) {
    $build = Join-Path $output "build-$runtime"
    $install = Join-Path $output "install-$runtime"
    RunCMake @('-S', $repository, '-B', $build, '-G', $Generator, '-A', 'x64', "-DUniversalDevKitRuntime=$runtime", "-DCMAKE_INSTALL_PREFIX=$install", ('-DUniversalDevKit_COMPONENTS=' + ($selected -join ';')))
    foreach ($configuration in @('Debug', 'Release')) {
        RunCMake @('--build', $build, '--config', $configuration)
        RunCMake @('--install', $build, '--config', $configuration)
        $metadata = if ($hasBinaries) {
            Get-Content (Join-Path $install "lib/cmake/UniversalDevKit/UniversalDevKit.Build-$configuration.json") -Raw | ConvertFrom-Json
        } else {
            # Выпуск только заголовков не содержит бинарного манифеста или ограничений CRT/ABI.
            [pscustomobject]@{ schemaVersion = 1; platform = 'Windows'; architecture = 'x64'; compilerId = 'MSVC'; runtime = $runtime; version = $version; toolset = ''; compilerVersion = ''; components = @(); runtimeFiles = @() }
        }
        if ($metadata.schemaVersion -ne 1 -or $metadata.platform -ne 'Windows' -or $metadata.architecture -ne 'x64' -or
            $metadata.compilerId -ne 'MSVC' -or $metadata.runtime -ne $runtime -or $metadata.version -ne $version) { throw 'Unexpected binary release metadata.' }
        $records += [pscustomobject]@{ Runtime = $runtime; Configuration = $configuration; Install = $install; Metadata = $metadata }
    }
}

# 5. Проверяем единство compiler/toolset; версия tools не обязана совпадать с версией cl.exe.
$toolset = $records[0].Metadata.toolset
$compiler = $records[0].Metadata.compilerVersion
$cache = Get-Content (Join-Path $output 'build-Dynamic/CMakeCache.txt') -Raw
$vcTools = [regex]::Match($cache, '/MSVC/([^/]+)/bin/').Groups[1].Value
if ($hasBinaries -and -not $vcTools) { throw 'Cannot determine actual VCToolsVersion.' }
foreach ($record in $records) {
    if ($record.Metadata.toolset -ne $toolset -or $record.Metadata.compilerVersion -ne $compiler) { throw 'Cannot combine compilers in one NuGet release.' }
}

# 6. Для каждого компонента создаём собственный пакет; чужие бинарники остаются в зависимых пакетах.
foreach ($component in $selected) {
    # Новый staging не переносит устаревшие файлы из предыдущего выпуска.
    $stage = Join-Path $output ('staging/' + $component + '-' + [Guid]::NewGuid().ToString('N'))
    $payload = Join-Path $stage 'payload'
    [void][IO.Directory]::CreateDirectory((Join-Path $payload 'include'))
    Copy-Item -LiteralPath $license -Destination (Join-Path $payload 'LICENSE.txt')
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'README.md') -Destination (Join-Path $payload 'README.md')

    # Общие API-заголовки и заголовки компонента сохраняют публичные include-пути.
    foreach ($headerRoot in @('Includes/Core', "Includes/$component")) {
        $sourceRoot = Join-Path $repository $headerRoot
        foreach ($header in Get-ChildItem -LiteralPath $sourceRoot -File -Recurse) {
            $relative = $header.FullName.Substring($sourceRoot.Length + 1)
            $headerDestination = Join-Path $payload "include/$relative"
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($headerDestination))
            Copy-Item -LiteralPath $header.FullName -Destination $headerDestination -Force
        }
    }
    $variants = [Collections.Generic.List[string]]::new()
    $componentGraphs = @($graphs.Keys | Where-Object { $_.StartsWith($component + '.', [StringComparison]::Ordinal) } | Sort-Object)
    foreach ($record in $records) {
        $runtime = $record.Runtime
        $configuration = $record.Configuration
        $destination = Join-Path $payload "binaries/$runtime/$configuration"
        [void][IO.Directory]::CreateDirectory($destination)
        if ($hasBinaries) { Copy-Item -LiteralPath (Join-Path $record.Install "lib/cmake/UniversalDevKit/UniversalDevKit.Build-$configuration.json") -Destination (Join-Path $destination 'Release.json') }

        # Кладём в пакет только собственные библиотеки и DLL этой конфигурации.
        foreach ($entry in @($record.Metadata.components | Where-Object { $_.name -ceq $component })) {
            Copy-Item -LiteralPath (Join-Path $record.Install $entry.linkFile) -Destination $destination
            if ($entry.variant -eq 'Dynamic') { Copy-Item -LiteralPath (Join-Path $record.Install (GetDll $record $component)) -Destination $destination }
        }

        # Генерируем настройки consumer отдельно для каждого режима и CRT/конфигурации.
        foreach ($key in $componentGraphs) {
            $mode = $key.Substring($component.Length + 1)
            $graph = $graphs[$key]
            $condition = (RootCondition $component $mode) + " and '`$(UniversalDevKitRuntime)' == '$runtime' and '`$(Configuration)' == '$configuration'"
            $root = '$(__UniversalDevKit' + $component + 'PackageRoot)'
            $guard = "binaries\$runtime\$configuration\Abi.h"
            if ($hasBinaries) {
                # Принудительный include проверяет фактические настройки каждой единицы компиляции.
                Copy-Item -LiteralPath (Join-Path $record.Install "lib/cmake/UniversalDevKit/UniversalDevKit.Abi-$configuration.h") -Destination (Join-Path $destination 'Abi.h')
                $compilerParts = $compiler -split '\.'
                $fullCompiler = $compilerParts[0] + $compilerParts[1] + $compilerParts[2]
                $abiText = Get-Content (Join-Path $destination 'Abi.h') -Raw
                WriteGenerated (Join-Path $destination 'Abi.h') ($abiText.TrimEnd() + "`n#if _MSC_FULL_VER != $fullCompiler`n#error UniversalDevKit package exact compiler mismatch`n#endif")
            }
            $definitions = (@($graph.DefinitionComponents | ForEach-Object { 'UNIVERSALDEVKIT_' + $_.ToUpperInvariant() + '_DYNAMIC' }) -join ';') + ';'
            $includes = (@($graph.RequirementComponents | ForEach-Object { (PackageRoot $_) + 'include' }) -join ';') + ';'
            $link = ''

            # Static раскрывает зависимости финальному линкеру; private Static внутри DLL туда не попадает.
            foreach ($name in $graph.LinkComponents) {
                if ($registry[$name].Kind -eq 'headerOnly') { continue }
                $entry = GetEntry $record $name $graph.ResolvedModes[$name]
                $link += (PackageRoot $name) + "binaries\$runtime\$configuration\" + (Split-Path $entry.linkFile -Leaf) + ';'
            }

            # Системные библиотеки добавляются для требующих их статических реализаций.
            foreach ($name in $graph.SystemLibraryComponents) {
                foreach ($library in $registry[$name].Requirements.Libraries['Windows']) {
                    $link += $library + $(if ($library.EndsWith('.lib')) { ';' } else { '.lib;' })
                }
            }
            $forced = if ($hasBinaries) { "$root$guard;" } else { '' }
            $variants.Add("  <ItemDefinitionGroup Condition=`"$condition`"><ClCompile><AdditionalIncludeDirectories>$includes%(AdditionalIncludeDirectories)</AdditionalIncludeDirectories><ForcedIncludeFiles>$forced%(ForcedIncludeFiles)</ForcedIncludeFiles><PreprocessorDefinitions>$definitions%(PreprocessorDefinitions)</PreprocessorDefinitions></ClCompile><Link><AdditionalDependencies>$link%(AdditionalDependencies)</AdditionalDependencies></Link></ItemDefinitionGroup>")

            # Runtime-набор включает и внутренние транзитивные DLL, не только прямые ссылки consumer.
            foreach ($name in $graph.RuntimeComponents) {
                $dllName = Split-Path (GetDll $record $name) -Leaf
                $path = (PackageRoot $name) + "binaries\$runtime\$configuration\$dllName"
                $variants.Add("  <ItemGroup Condition=`"$condition`"><__UniversalDevKit${component}NuGetRuntime Include=`"$path`" /></ItemGroup>")
            }
        }
    }

    # 7. Формируем проверки restore/версий и конфликтов между графами выбранных корней.
    $checks = [Collections.Generic.List[string]]::new()
    foreach ($key in $componentGraphs) {
        $mode = $key.Substring($component.Length + 1)
        $graph = $graphs[$key]
        $condition = RootCondition $component $mode

        # Проверяем наличие imports всех зависимых пакетов и точное совпадение версии выпуска.
        foreach ($name in $graph.ResolvedComponents) {
            $checks.Add('    <Error Condition="' + $condition + ' and ''$(__UniversalDevKit' + $name + 'PackageVersion)'' != ''@VERSION@''" Text="Restore/import UniversalDevKit.' + $name + ' of the exact release version." />')
        }

        # Два независимых корня могут требовать разные варианты одного транзитивного компонента.
        foreach ($otherKey in @($graphs.Keys | Sort-Object)) {
            $separator = $otherKey.LastIndexOf('.')
            $other = $otherKey.Substring(0, $separator)
            if ($other -eq $component) { continue }
            $otherMode = $otherKey.Substring($separator + 1)
            $otherGraph = $graphs[$otherKey]
            foreach ($name in $graph.ResolvedComponents) {
                if ($otherGraph.ResolvedModes.ContainsKey($name) -and $otherGraph.ResolvedModes[$name] -ne $graph.ResolvedModes[$name]) {
                    $both = $condition + ' and ' + (RootCondition $other $otherMode)
                    $checks.Add('    <Error Condition="' + $both + '" Text="Conflicting NuGet linkage for ' + $name + ': ' + $key + ' versus ' + $otherKey + '." />')
                }
            }
        }
    }

    # 8. Заполняем общие шаблоны; NuGet-зависимости доставляют файлы, граф определяет их использование.
    $dependencies = (@($registry[$component].Dependencies | ForEach-Object { '<dependency id="UniversalDevKit.' + $_.Component + '" version="[' + $version + ']" />' }) -join '')
    $defaultMode = if ($registry[$component].Kind -eq 'headerOnly') { 'Shared' } elseif ($registry[$component].StateScope -eq 'process') { 'Dynamic' } else { 'Static' }
    $target = Get-Content (Join-Path $PSScriptRoot 'Templates/Component.targets.in') -Raw
    $target = $target.Replace('@COMPONENT@', $component).Replace('@VARIANTS@', ($variants -join "`n")).Replace('@TOOLSET@', $toolset).Replace('@VCTOOLS@', $vcTools).Replace('@DEPENDENCY_CHECKS@', ($checks -join "`n")).Replace('@DEFAULT_MODE@', $defaultMode)
    $validModes = (@($componentGraphs | ForEach-Object { $_.Substring($component.Length + 1) }) -join ';')
    $target = $target.Replace('@VERSION@', $version).Replace('@VALID_MODES@', $validModes).Replace('@HAS_BINARIES@', $hasBinaries.ToString().ToLowerInvariant())
    $unknown = (@($selected | ForEach-Object { "'%(__UniversalDevKitNuGetRoot.Identity)' != '$_'" }) -join ' and ')
    $target = $target.Replace('@UNKNOWN_ROOT@', $unknown)
    WriteGenerated (Join-Path $payload "build/native/UniversalDevKit.$component.targets") $target
    $props = Get-Content (Join-Path $PSScriptRoot 'Templates/Component.props.in') -Raw
    WriteGenerated (Join-Path $payload "build/native/UniversalDevKit.$component.props") ($props.Replace('@COMPONENT@', $component).Replace('@VERSION@', $version).Replace('@DEFAULT_MODE@', $defaultMode))
    $spec = Get-Content (Join-Path $PSScriptRoot 'Templates/Component.nuspec.in') -Raw
    WriteGenerated (Join-Path $stage "$component.nuspec") ($spec.Replace('@COMPONENT@', $component).Replace('@VERSION@', $version).Replace('@DEPENDENCIES@', $dependencies))

    # 9. Создаём локальный .nupkg; публикация в feed этим скриптом не выполняется.
    # Native DLL подключаются targets, поэтому предупреждения для managed lib/ref неприменимы.
    & $NuGet pack (Join-Path $stage "$component.nuspec") -BasePath $stage -OutputDirectory $output -NonInteractive -Properties 'NoWarn=NU5100;NU5128' | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "NuGet pack failed for $component" }
}
Write-Host "NuGet feed: $output"