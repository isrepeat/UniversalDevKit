param(
    [string]$AndroidNdk,
    [string]$CMake,
    [string]$Ninja,
    [ValidateSet('arm64-v8a', 'x86_64')][string[]]$Abi = @('arm64-v8a', 'x86_64'),
    [ValidateSet('Debug', 'Release')][string]$Configuration = 'Release',
    [ValidateRange(24, 35)][int]$ApiLevel = 24,
    [string[]]$Components,
    [string]$OutputDirectory,
    [string]$BuildRoot,
    [string]$RepositoryPath
)

# 1. Настраиваем язык сообщений, кодировку консоли и остановку при ошибках.
$env:DOTNET_CLI_UI_LANGUAGE = 'en-US'
$env:VSLANG = '1033'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)
$ErrorActionPreference = 'Stop'

# 2. Находим репозиторий и проверяем Android NDK, CMake и Ninja.
if (-not $RepositoryPath) {
    $RepositoryPath = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
}
$repository = (Resolve-Path -LiteralPath $RepositoryPath).Path
. (Join-Path $PSScriptRoot '../../../Scripts/Android/ResolveToolchain.ps1')
$AndroidNdk = (Resolve-UdkAndroidToolchain -AndroidNdk $AndroidNdk).AndroidNdk
$AndroidNdk = (Resolve-Path -LiteralPath $AndroidNdk).Path
$revision = ((Get-Content (Join-Path $AndroidNdk 'source.properties') | Where-Object { $_ -match '^Pkg.Revision\s*=' }) -split '=')[1].Trim()
$ndkMajor = [int]$revision.Split('.')[0]
if ($ndkMajor -ne 27) {
    throw 'The initial Android profile requires NDK r27 and c++_shared.'
}

if (-not $CMake) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    $CMake = @(& $vswhere -latest -products '*' -find 'Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe')[0]
}

if (-not $Ninja) {
    $Ninja = Join-Path (Split-Path $CMake -Parent) 'ninja.exe'
    if (-not (Test-Path -LiteralPath $Ninja)) {
        $Ninja = Join-Path (Split-Path (Split-Path (Split-Path $CMake -Parent) -Parent) -Parent) 'Ninja/ninja.exe'
    }
}
if (-not (Test-Path -LiteralPath $Ninja)) {
    throw 'Pass the path to ninja.exe with -Ninja.'
}

# 3. Читаем реестр компонентов и их Android-адаптеры из Package.json.
Import-Module (Join-Path $repository 'Scripts/PowerShell/Modules/Module.Udk.Connection/Module.Udk.Connection.psm1') -Force
. (Join-Path $repository 'Scripts/PowerShell/Modules/Module.Udk.Connection/Private/ConnectionPlan.ps1')
$registry = Get-UdkComponentRegistry $repository
$deliveries = @{}
foreach ($file in Get-ChildItem (Join-Path $repository 'Packages') -Filter 'Package.json' -Recurse -File) {
    $package = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
    if (-not $package.deliveries.Android -or -not $package.component) {
        continue
    }
    if ($deliveries.ContainsKey($package.component)) {
        throw "Duplicate Android adapter: $($package.component)"
    }
    $delivery = Get-Content (Join-Path $file.DirectoryName $package.deliveries.Android) -Raw | ConvertFrom-Json
    if ($delivery.schemaVersion -ne 1 -or $delivery.groupId -notmatch '^[a-z][a-z0-9.]+$' -or $delivery.artifactPrefix -notmatch '^[a-z][a-z0-9-]+$') {
        throw "Invalid Android delivery: $($file.FullName)"
    }
    $deliveries[$package.component] = $delivery
}
if (-not $Components) {
    $Components = @($registry.Keys | Sort-Object)
}
foreach ($component in $Components) {
    if (-not $registry.ContainsKey($component) -or -not $deliveries.ContainsKey($component)) {
        throw "Missing Android component/adapter: $component"
    }
}

# 4. Выбираем версию, каталог Maven-feed и изолированное дерево сборки.
$version = (Get-Content (Join-Path $repository 'Version.json') -Raw | ConvertFrom-Json).version
$output = if ($OutputDirectory) {
    [IO.Path]::GetFullPath($OutputDirectory)
} else {
    Join-Path $repository '!artifacts/Android/packages'
}
$work = if ($BuildRoot) {
    [IO.Path]::GetFullPath($BuildRoot)
} else {
    Join-Path $repository ('!artifacts/Android/cmake/pack-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
}
if (-not $work.StartsWith((Join-Path $repository '!artifacts/'), [StringComparison]::OrdinalIgnoreCase)) {
    throw 'BuildRoot must be inside the repository artifacts directory.'
}
[void][IO.Directory]::CreateDirectory($work)

# Вспомогательные функции сохраняют метаданные без завершающих переводов строк.
function WriteText([string]$Path, [string]$Text) {
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    [IO.File]::WriteAllText($Path, $Text.TrimEnd([char[]]"`r`n"), [Text.UTF8Encoding]::new($false))
}

function WriteJson([string]$Path, $Value) {
    WriteText $Path ($Value | ConvertTo-Json -Depth 30)
}

# Ненулевой код CMake прерывает упаковку, чтобы не выпускать неполный пакет.
function RunCMake([string[]]$Arguments) {
    & $CMake @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw 'Android CMake build failed.'
    }
}

# 5. Собираем и устанавливаем общие исходники отдельно для каждого ABI.
# Метаданные установки содержат фактические имена библиотек, а не предполагаемые пути.
$records = @{}
$compiledComponents = @($Components | Where-Object { $registry[$_].Kind -ne 'headerOnly' })
foreach ($architecture in $(if ($compiledComponents.Count) { $Abi } else { @() })) {
    $build = Join-Path $work $architecture
    $prefix = Join-Path $build 'install'

    # Режим драйвера задаётся явно: Windows short path теряет суффикс ++ у clang++.
    RunCMake @(
        '-S',
        $repository,
        '-B',
        $build,
        '-G',
        'Ninja',
        "-DCMAKE_MAKE_PROGRAM=$Ninja",
        "-DCMAKE_TOOLCHAIN_FILE=$AndroidNdk/build/cmake/android.toolchain.cmake",
        '-DCMAKE_CXX_COMPILER_ARG1=--driver-mode=g++',
        '-DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON',
        "-DANDROID_ABI=$architecture",
        "-DANDROID_PLATFORM=android-$ApiLevel",
        '-DANDROID_STL=c++_shared',
        "-DCMAKE_BUILD_TYPE=$Configuration",
        "-DCMAKE_INSTALL_PREFIX=$prefix",
        "-DUniversalDevKit_COMPONENTS=$($compiledComponents -join ';')"
    )
    RunCMake @('--build', $build, '--parallel', '4')
    RunCMake @('--install', $build)
    $metadata = Get-Content (Join-Path $prefix "lib/cmake/UniversalDevKit/UniversalDevKit.Build-$Configuration.json") -Raw | ConvertFrom-Json
    if ($metadata.platform -ne 'Android') {
        throw 'Expected Android build metadata.'
    }
    $records[$architecture] = @{ Prefix = $prefix; Metadata = $metadata }
}

# Для AAR используем ZIP с прямыми слешами независимо от ОС упаковщика.
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression

function ModuleName([string]$Component, [string]$Mode) {
    return ($Component + '_' + $Mode).ToLowerInvariant()
}

# 6. Формируем отдельный AAR для каждого корня и разрешённого варианта.
# Process-компонент допускает только Dynamic; private-зависимости не раскрывают заголовки.
foreach ($component in $Components) {
    if (-not $registry.ContainsKey($component)) {
        throw "Unknown component: $component"
    }
    $modes = if ($registry[$component].Kind -eq 'headerOnly') {
        @('Shared')
    } elseif ($registry[$component].StateScope -eq 'process') {
        @('Dynamic')
    } else {
        @('Static', 'Dynamic')
    }
    foreach ($mode in $modes) {
        # 6.1. Рассчитываем граф и создаём новый staging для текущего артефакта.
        $graph = Resolve-UdkLinkageGraph @($component) @{ $component = $mode } $registry
        $packageName = 'udk_' + (ModuleName $component $mode)
        $delivery = $deliveries[$component]
        $artifact = $delivery.artifactPrefix + '-' + $mode.ToLowerInvariant() + '-' + $Configuration.ToLowerInvariant()
        $stage = Join-Path $work ('stage-' + [Guid]::NewGuid().ToString('N').Substring(0, 8) + '/' + $artifact)

        # 6.2. Записываем Android/Prefab-манифесты и собираем только публичные заголовки.
        WriteText (Join-Path $stage 'AndroidManifest.xml') ('<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="org.universaldevkit.' + $packageName + '"><uses-sdk android:minSdkVersion="' + $ApiLevel + '"/></manifest>')
        WriteJson (Join-Path $stage 'prefab/prefab.json') @{
            schema_version = 2
            name = $packageName
            version = $version
            dependencies = @()
        }
        $linkSet = @(@($graph.LinkComponents) + @($graph.RuntimeComponents) | Where-Object { $registry[$_].Kind -ne 'headerOnly' } | Sort-Object -Unique)
        $rootModule = Join-Path $stage "prefab/modules/$component"
        $include = Join-Path $rootModule 'include'
        [void][IO.Directory]::CreateDirectory($include)
        Copy-Item (Join-Path $repository 'Includes/Core/*') $include -Recurse
        foreach ($requirement in $graph.RequirementComponents) {
            Copy-Item (Join-Path $repository "Includes/$requirement/*") $include -Recurse -Force
            if ($graph.ResolvedModes[$requirement] -eq 'Dynamic') {
                $export = Join-Path $include "UniversalDevKit/$requirement/Export.h"
                $macro = 'UNIVERSALDEVKIT_' + $requirement.ToUpperInvariant() + '_DYNAMIC'
                WriteText $export ("// Generated by Android/Build.ps1. Source: component export header.`n#pragma once`n#ifndef $macro`n#define $macro`n#endif`n" + [IO.File]::ReadAllText($export))
            }
        }

        # 6.3. Сохраняем контракт, который consumer проверит перед линковкой.
        $standard = ($graph.RequirementComponents | ForEach-Object { $registry[$_].Requirements.CxxStandard } | Measure-Object -Maximum).Maximum
        $contract = @{
            schemaVersion = 1
            version = $version
            ndk = $revision
            stl = 'c++_shared'
            api = $ApiLevel
            configuration = $Configuration
            modes = $graph.ResolvedModes
            package = $packageName
            component = $component
            cxxStandard = [int]$standard
            pageSize = 16384
        }
        WriteJson (Join-Path $include 'UniversalDevKit/Android/contract.json') $contract
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Consumer.cmake') -Destination (Join-Path $include 'UniversalDevKit/Android/Consumer.cmake')

        # Заголовочный модуль Prefab не содержит libs или фиктивных бинарников.
        WriteJson (Join-Path $rootModule 'module.json') @{
            export_libraries = @()
        }

        # 6.4. Описываем Prefab-модули и кладём бинарники всех выбранных ABI.
        # Внутренние модули участвуют в линковке/runtime без собственных include-путей.
        foreach ($name in $linkSet) {
            $resolvedMode = $graph.ResolvedModes[$name]
            $moduleName = if ($name -eq $component) {
                $component
            } else {
                'internal_' + (ModuleName $name $resolvedMode)
            }
            $module = Join-Path $stage "prefab/modules/$moduleName"
            $exports = @()

            # Связи Prefab и системные библиотеки берём из того же графа, что использует сборка.
            foreach ($dependency in $registry[$name].Dependencies) {
                if ($dependency.Component -in $linkSet) {
                    $exports += ':internal_' + (ModuleName $dependency.Component $graph.ResolvedModes[$dependency.Component])
                }
            }
            $systemSources = if ($name -eq $component) {
                @($graph.SystemLibraryComponents)
           
            } elseif ($resolvedMode -eq 'Static') {
                @($name)
            } else {
                @()
            }
            foreach ($systemSource in $systemSources) {
                foreach ($library in @($registry[$systemSource].Requirements.Libraries.Android)) {
                    if ($library) {
                        $exports += '-l' + $library
                    }
                }
            }

            WriteJson (Join-Path $module 'module.json') @{
                export_libraries = @($exports)
            }
            foreach ($architecture in $Abi) {
                $record = $records[$architecture]
                $entries = @($record.Metadata.components | Where-Object { $_.name -ceq $name -and $_.variant -ceq $resolvedMode })
                if ($entries.Count -ne 1) {
                    throw "Missing Android artifact: $name.$resolvedMode"
                }
                $source = Join-Path $record.Prefix $entries[0].linkFile

                # Prefab использует имя модуля для выбора файла; SONAME shared-библиотеки сохраняется.
                $stem = [IO.Path]::GetFileNameWithoutExtension($source)
                WriteJson (Join-Path $module 'module.json') @{
                    library_name = $stem
                    export_libraries = @($exports)
                }
                $libs = Join-Path $module "libs/android.$architecture"
                [void][IO.Directory]::CreateDirectory($libs)
                Copy-Item -LiteralPath $source -Destination $libs
                WriteJson (Join-Path $libs 'abi.json') @{
                    abi = $architecture
                    api = $ApiLevel
                    ndk = $ndkMajor
                    stl = 'c++_shared'
                    static = ($resolvedMode -eq 'Static')
                }
            }
        }

        # 6.5. Добавляем лицензию и контракт выпуска, затем сохраняем AAR и POM в Maven-feed.
        Copy-Item -LiteralPath (Join-Path $repository 'LICENSE') -Destination (Join-Path $stage 'LICENSE.txt')
        WriteJson (Join-Path $stage 'udk-release.json') $contract

        # Maven сохраняет идентичность и версию; публикация во внешний сервер не выполняется.
        $groupPath = $delivery.groupId.Replace('.', '/')
        $destination = Join-Path $output "$groupPath/$artifact/$version"
        [void][IO.Directory]::CreateDirectory($destination)
        $aar = Join-Path $destination "$artifact-$version.aar"
        if (Test-Path -LiteralPath $aar) {
            throw "Refusing to overwrite a release: $aar. Use a fresh output directory."
        }

        # .NET Framework создаёт обратные слеши в ZIP; для Android нужны обычные ZIP-пути.
        $stream = [IO.File]::Open($aar, [IO.FileMode]::CreateNew)
        $archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($file in Get-ChildItem -LiteralPath $stage -Recurse -File) {
                $relative = $file.FullName.Substring($stage.Length + 1).Replace('\', '/')
                [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $file.FullName, $relative)
            }
        }
        finally {
            $archive.Dispose()
            $stream.Dispose()
        }

        WriteText (Join-Path $destination "$artifact-$version.pom") ('<project xmlns="http://maven.apache.org/POM/4.0.0"><modelVersion>4.0.0</modelVersion><groupId>' + $delivery.groupId + '</groupId><artifactId>' + $artifact + '</artifactId><version>' + $version + '</version><packaging>aar</packaging><licenses><license><name>MIT</name><url>https://opensource.org/licenses/MIT</url></license></licenses></project>')
        Write-Host "Android package: $aar"
    }
}

# 7. Выводим путь к готовому локальному feed; внешняя публикация не выполняется.
Write-Host "Android Maven feed: $output"