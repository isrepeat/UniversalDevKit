function Initialize-AndroidBuildConsole {
    # Задаём единый формат для сообщений PowerShell и данных, передаваемых
    # внешним программам через pipeline. Кодировку вывода самой программы
    # без поддержки UTF-8 эта функция изменить не может.
    $utf8Encoding = [System.Text.UTF8Encoding]::new($false)
    [Console]::InputEncoding = $utf8Encoding
    [Console]::OutputEncoding = $utf8Encoding
    $global:OutputEncoding = $utf8Encoding
}

function Import-AndroidBuildDataFile {
    param([Parameter(Mandatory)] [string]$Path)

    # android-build.psd1 — контролируемый файл конфигурации проекта. Не зависим
    # от Import-PowerShellDataFile: в урезанном окружении CMake этот cmdlet
    # может отсутствовать даже в Windows PowerShell.
    $config = & ([scriptblock]::Create([System.IO.File]::ReadAllText($Path)))
    if ($config -isnot [hashtable]) {
        throw "Configuration must return a hashtable: $Path"
    }
    return $config
}

function Read-AndroidBuildConfiguration {
    param([Parameter(Mandatory)] [string]$ProjectRoot)

    $config = Import-AndroidBuildDataFile (Join-Path $ProjectRoot 'android-build.psd1')
    foreach ($name in @('ArtifactName', 'AndroidModule', 'GradleRoot', 'VersionFile', 'DistributionDirectory', 'PackageDirectories')) {
        if ([string]::IsNullOrWhiteSpace($config[$name])) {
            throw "android-build.psd1 must define $name."
        }
    }
    return $config
}

function Read-AndroidBuildSharedConfiguration {
    param([Parameter(Mandatory)] [string]$ProjectRoot)

    # Общие настройки читаются отдельно и не изменяют конфигурацию проекта.
    . (Join-Path $PSScriptRoot '..\..\Read-AndroidSharedProps.ps1')
    return Read-AndroidSharedProps -ProjectRoot $ProjectRoot
}

function Get-AndroidBuildConfigurationValue {
    param(
        [Parameter(Mandatory)] [hashtable]$Configuration,
        [Parameter(Mandatory)] [string]$Name
    )

    $value = $Configuration
    foreach ($segment in $Name.Split('.')) {
        if ($value -isnot [hashtable] -or -not $value.ContainsKey($segment)) {
            throw "android-build.psd1 must define $Name."
        }
        $value = $value[$segment]
    }
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "android-build.psd1 must define $Name."
    }
    return $value
}

function Resolve-AndroidBuildTools {
    param([string]$CMakeExecutable)

    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) {
        throw 'Visual Studio Installer was not found. Install Visual Studio with Desktop development with C++ and CMake tools.'
    }
    $instances = @(& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -format json | ConvertFrom-Json)
    if ($instances.Count -eq 0) {
        throw 'Visual Studio C++ tools were not found. Install Desktop development with C++.'
    }
    $instance = $instances[0]
    $major = ([version]$instance.installationVersion).Major
    $generators = @{ 17 = 'Visual Studio 17 2022'; 18 = 'Visual Studio 18 2026' }
    if (-not $generators.ContainsKey($major)) {
        throw "Unsupported Visual Studio version: $($instance.installationVersion)"
    }
    $cmakeRoot = Join-Path $instance.installationPath 'Common7\IDE\CommonExtensions\Microsoft\CMake'
    if (-not $CMakeExecutable) {
        $CMakeExecutable = Join-Path $cmakeRoot 'CMake\bin\cmake.exe'
    }
    if (-not (Test-Path -LiteralPath $CMakeExecutable)) {
        throw "CMake was not found at $CMakeExecutable. Install C++ CMake tools for Windows."
    }
    return @{ CMake = $CMakeExecutable; Ninja = (Join-Path $cmakeRoot 'Ninja\ninja.exe'); VisualStudio = $instance.installationPath; Generator = $generators[$major] }
}

function Resolve-AndroidJavaHome {
    $candidateRoots = @(
        $env:JAVA_HOME,
        $env:JDK_HOME,
        (Join-Path $env:ProgramFiles 'Android\Android Studio\jbr'),
        (Join-Path $env:ProgramFiles 'Android\openjdk'),
        (Join-Path $env:ProgramFiles 'Java')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($candidateRoot in $candidateRoots) {
        $homes = @($candidateRoot)
        if (Test-Path -LiteralPath $candidateRoot -PathType Container) {
            $homes += Get-ChildItem -LiteralPath $candidateRoot -Directory -ErrorAction SilentlyContinue |
                Sort-Object Name -Descending |
                ForEach-Object FullName
        }
        foreach ($javaHomeCandidate in $homes) {
            if (Test-Path -LiteralPath (Join-Path $javaHomeCandidate 'bin\java.exe') -PathType Leaf) {
                return $javaHomeCandidate
            }
        }
    }

    throw 'Java JDK was not found. Set JAVA_HOME or install Android Studio / Android OpenJDK.'
}

function Resolve-AndroidSdk {
    $candidateRoots = @(
        $env:ANDROID_HOME,
        $env:ANDROID_SDK_ROOT,
        (Join-Path $env:LOCALAPPDATA 'Android\Sdk'),
        (Join-Path ${env:ProgramFiles(x86)} 'Android\android-sdk'),
        (Join-Path $env:ProgramFiles 'Android\Sdk')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($candidateRoot in $candidateRoots) {
        if (Test-Path -LiteralPath (Join-Path $candidateRoot 'platform-tools\adb.exe') -PathType Leaf) {
            return $candidateRoot
        }
    }

    throw 'Android SDK was not found. Set ANDROID_HOME or install the Android SDK platform tools.'
}

function Resolve-LatestNuGetPackageVersion {
    param(
        [Parameter(Mandatory)] [string]$PackageName,
        [Parameter(Mandatory)] [string]$Source
    )

    $nuget = (Get-Command nuget.exe -ErrorAction Stop).Source
    $availablePackages = & $nuget list $PackageName -Source $Source -AllVersions -NonInteractive -ForceEnglishOutput 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "$PackageName version lookup failed for $Source."
    }

    $versions = $availablePackages | ForEach-Object {
        $match = [regex]::Match($_.ToString(), "^\s*$([regex]::Escape($PackageName))\s+(\d+(?:\.\d+){2,3})\s*$")
        if ($match.Success) {
            [version]$match.Groups[1].Value
        }
    }
    return $versions | Sort-Object -Descending | Select-Object -First 1
}

function Get-AndroidGradlePackages {
    param(
        [Parameter(Mandatory)] [string]$ProjectRoot,
        [Parameter(Mandatory)] [hashtable]$Configuration
    )

    $moduleBuildFile = Join-Path (Join-Path $ProjectRoot $Configuration.AndroidModule) 'build.gradle.kts'
    if (-not (Test-Path -LiteralPath $moduleBuildFile -PathType Leaf)) {
        return @()
    }

    $pattern = '(?m)^\s*(?<scope>api|implementation|compileOnly|runtimeOnly|testImplementation|androidTestImplementation)\s*\(\s*"(?<group>[^":]+):(?<artifact>[^":]+):(?<version>[^"]+)"\s*\)'
    return [regex]::Matches([System.IO.File]::ReadAllText($moduleBuildFile), $pattern) | ForEach-Object {
        [pscustomobject]@{
            Scope = $_.Groups['scope'].Value
            Name = "$($_.Groups['group'].Value):$($_.Groups['artifact'].Value)"
            Version = $_.Groups['version'].Value
        }
    }
}

function Show-AndroidBuildInputs {
    param(
        [Parameter(Mandatory)] [string]$ProjectRoot,
        [Parameter(Mandatory)] [ValidateSet('Debug', 'Release')] [string]$Configuration
    )

    $androidProjectConfig = Read-AndroidBuildConfiguration $ProjectRoot
    $androidProjectSharedConfig = Read-AndroidBuildSharedConfiguration $ProjectRoot
    $hasNativeBuild = $null -ne $androidProjectConfig.Native -or -not [string]::IsNullOrWhiteSpace($androidProjectConfig.NativeLibrary)

    Write-Host '==> Build inputs'
    Write-Host "Application: $($androidProjectConfig.ArtifactName)"
    Write-Host "Configuration: $Configuration"
    Write-Host "Package feed: $($androidProjectSharedConfig.Paths.PackagesFeed)"
    Write-Host 'NuGet packages:'
    Write-Host "  AndroidBuildTools $($androidProjectConfig.AndroidBuildToolsVersion)"
    if ($androidProjectConfig.Xaml) {
        $xamlRuntimeVersion = Resolve-LatestNuGetPackageVersion -PackageName 'UniversalDevKit.XamlCompiler' -Source $androidProjectSharedConfig.Paths.PackagesFeed
        Write-Host "  UniversalDevKit.XamlCompiler $xamlRuntimeVersion"
    }

    $gradlePackages = Get-AndroidGradlePackages -ProjectRoot $ProjectRoot -Configuration $androidProjectConfig
    if ($gradlePackages.Count -gt 0) {
        Write-Host 'Gradle packages:'
        foreach ($gradlePackage in $gradlePackages) {
            Write-Host "  $($gradlePackage.Scope) $($gradlePackage.Name) $($gradlePackage.Version)"
        }
    }

    $javaHome = Resolve-AndroidJavaHome
    $androidSdk = Resolve-AndroidSdk
    Write-Host 'Android tools:'
    Write-Host "  Java: $javaHome"
    Write-Host "  Android SDK: $androidSdk"
    if ($hasNativeBuild) {
        $tools = Resolve-AndroidBuildTools
        Write-Host "  CMake: $($tools.CMake)"
        Write-Host "  Ninja: $($tools.Ninja)"
    }
}

function Resolve-AndroidBuildConfigurationPath {
    param(
        [Parameter(Mandatory)] [hashtable]$Configuration,
        [Parameter(Mandatory)] [string]$ProjectRoot,
        [Parameter(Mandatory)] [string]$Name
    )

    $value = Get-AndroidBuildConfigurationValue -Configuration $Configuration -Name $Name
    return [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot $value))
}

function Resolve-XamlCompiler {
    param(
        [Parameter(Mandatory)] [string]$PackagesRoot,
        [Parameter(Mandatory)] [string]$Source
    )

    $packageName = 'UniversalDevKit.XamlCompiler'
    # Локальный feed проверяем по версиям архивов без запуска NuGet.
    if (Test-Path -LiteralPath $Source -PathType Container) {
        $archives = Get-ChildItem -LiteralPath $Source -Filter "$packageName.*.nupkg" -File |
            ForEach-Object {
                $parsedVersion = $null
                $versionText = $_.BaseName.Substring($packageName.Length + 1)
                if ([version]::TryParse($versionText, [ref]$parsedVersion)) {
                    [pscustomobject]@{ Archive = $_; Version = $parsedVersion }
                }
            } | Sort-Object Version -Descending
        $latest = $archives | Select-Object -First 1
        if ($null -ne $latest) {
            $packageDirectory = Join-Path $PackagesRoot $latest.Archive.BaseName
            $compiler = Join-Path $packageDirectory 'tools\win-x64\XamlCompiler.exe'
            if (Test-Path -LiteralPath $compiler -PathType Leaf) {
                return $compiler
            }
        }
    }
    $nuget = (Get-Command nuget.exe -ErrorAction Stop).Source

    # Для удалённого feed или отсутствующей версии выполняем обычный restore.
    & $nuget install $packageName -Source $Source -OutputDirectory $PackagesRoot -NonInteractive -ForceEnglishOutput -Verbosity quiet | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "XamlRuntime restore failed with exit code $LASTEXITCODE."
    }

    # NuGet распаковывает каждую версию в каталог XamlRuntime.<версия>.
    # Сортировка версий ставит 1.0.23 выше 1.0.9.
    $candidates = Get-ChildItem -LiteralPath $PackagesRoot -Directory -Filter "$packageName.*" |
        Sort-Object @{ Expression = {
                [version]$_.Name.Substring($packageName.Length + 1)
            }; Descending = $true }
    foreach ($candidate in $candidates) {
        $compiler = Join-Path $candidate.FullName 'tools\win-x64\XamlCompiler.exe'
        if (Test-Path -LiteralPath $compiler -PathType Leaf) {
            return $compiler
        }
    }

    throw "NuGet package $packageName did not provide tools\\win-x64\\XamlCompiler.exe in $PackagesRoot."
}

Export-ModuleMember -Function `
    Initialize-AndroidBuildConsole, `
    Read-AndroidBuildConfiguration, `
    Read-AndroidBuildSharedConfiguration, `
    Get-AndroidBuildConfigurationValue, `
    Resolve-AndroidBuildTools, `
    Resolve-AndroidJavaHome, `
    Resolve-AndroidSdk, `
    Resolve-LatestNuGetPackageVersion, `
    Get-AndroidGradlePackages, `
    Show-AndroidBuildInputs, `
    Resolve-AndroidBuildConfigurationPath, `
    Resolve-XamlCompiler