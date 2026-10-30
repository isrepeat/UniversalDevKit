[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ProjectRoot,

    [switch]$BuildOnly,

    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Debug',

    [int]$ParentProcessId = 0
)

$ErrorActionPreference = 'Stop'
$timer = [Diagnostics.Stopwatch]::StartNew()
$previousGeneratedProject = $env:ANDROID_BUILD_XAML_GENERATED_PROJECT
function Initialize-VisualStudioEnvironment {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VisualStudioRoot
    )

    # Передаём окружение Visual Studio компилятору, запущенному через Ninja.
    $developerCommand = Join-Path $VisualStudioRoot 'Common7\Tools\VsDevCmd.bat'
    if (-not (Test-Path -LiteralPath $developerCommand)) {
        throw "Visual Studio developer command was not found: $developerCommand"
    }

    $environmentLines = & cmd.exe /c "`"$developerCommand`" -arch=x64 -host_arch=x64 >nul && set"
    if ($LASTEXITCODE -ne 0) { throw 'Visual Studio environment initialization failed.' }
    foreach ($environmentLine in $environmentLines) {
        $separatorIndex = $environmentLine.IndexOf('=')
        if ($separatorIndex -gt 0) {
            $name = $environmentLine.Substring(0, $separatorIndex)
            $value = $environmentLine.Substring($separatorIndex + 1)
            Set-Item -LiteralPath "Env:$name" -Value $value
        }
    }
}

try {
    Write-Host '==> Checking preview build inputs'
    Import-Module -Name (Join-Path $PSScriptRoot 'Modules\Module.AndroidBuildTools\Module.AndroidBuildTools.psm1') -ErrorAction Stop
    Module.AndroidBuildTools\Initialize-AndroidBuildConsole
    $androidProjectConfig = Module.AndroidBuildTools\Read-AndroidBuildConfiguration $ProjectRoot
    $androidProjectSharedConfig = Module.AndroidBuildTools\Read-AndroidBuildSharedConfiguration $ProjectRoot
    $tools = Module.AndroidBuildTools\Resolve-AndroidBuildTools
    $generateXamlScript = Join-Path $PSScriptRoot 'generate-xaml.ps1'
    $artifactDirectory = Join-Path $projectRoot $androidProjectConfig.Preview.ArtifactDirectory
    $plugin = Join-Path $artifactDirectory $androidProjectConfig.Preview.Plugin.Replace('{Configuration}', $Configuration)
    $visualStudioCmake = $tools.CMake
    $visualStudioNinja = $tools.Ninja
    $cmakeBuildDirectory = Join-Path $artifactDirectory 'Intermediate\CMake'

    Initialize-VisualStudioEnvironment -VisualStudioRoot $tools.VisualStudio

    if ($ParentProcessId -gt 0) {
        $parentProcess = Get-Process -Id $ParentProcessId -ErrorAction SilentlyContinue
        if ($null -ne $parentProcess) {
            $parentProcess.WaitForExit()
        }
    }

    $xamlPackages = Module.AndroidBuildTools\Resolve-AndroidBuildConfigurationPath -Configuration $androidProjectConfig -ProjectRoot $ProjectRoot -Name 'PackageDirectories.XamlRuntime'
    $compiler = Module.AndroidBuildTools\Resolve-XamlCompiler -PackagesRoot $xamlPackages -Source $androidProjectSharedConfig.Paths.PackagesFeed
    & $generateXamlScript -ProjectRoot $ProjectRoot -XamlCompiler $compiler
    # Пропуск повторной генерации действует только внутри текущего запуска.
    $env:ANDROID_BUILD_XAML_GENERATED_PROJECT = [IO.Path]::GetFullPath($ProjectRoot)

    Write-Host "==> Rebuilding Application preview plugin $Configuration x64"
    if (Test-Path $visualStudioCmake) {
        $cmake = $visualStudioCmake
    } else {
        $cmake = (Get-Command cmake.exe -ErrorAction Stop).Source
    }
    if (Test-Path $visualStudioNinja) {
        $ninja = $visualStudioNinja
    } else {
        $ninja = (Get-Command ninja.exe -ErrorAction Stop).Source
    }
    $cmakeArguments = @('-S', $projectRoot, '-B', $cmakeBuildDirectory, '-G', 'Ninja', "-DCMAKE_BUILD_TYPE=$Configuration", "-DCMAKE_MAKE_PROGRAM=$ninja")
    # Источник нативных пакетов передаётся из отдельной общей конфигурации.
    $cmakeArguments += "-DANDROID_PACKAGES_FEED=$($androidProjectSharedConfig.Paths.PackagesFeed)"
    $packageRoot = Split-Path -Parent $PSScriptRoot
    $sdkPackages = Module.AndroidBuildTools\Resolve-AndroidBuildConfigurationPath -Configuration $androidProjectConfig -ProjectRoot $ProjectRoot -Name 'PackageDirectories.AndroidAppPreviewerPluginSdk'
    $cmakeArguments += @(
        "-DANDROID_BUILD_TOOLS_ROOT=$packageRoot",
        "-DANDROID_BUILD_CONFIGURATION_PackageDirectories_XamlRuntime=$xamlPackages",
        "-DANDROID_BUILD_CONFIGURATION_PackageDirectories_AndroidAppPreviewerPluginSdk=$sdkPackages"
    )
    & $cmake @cmakeArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Application preview-plugin CMake configure failed with exit code $LASTEXITCODE."
    }
    & $cmake '--build' $cmakeBuildDirectory '--target' $androidProjectConfig.Preview.Target '--' '-j' '2'
    if ($LASTEXITCODE -ne 0) {
        throw "Application preview plugin $Configuration build failed with exit code $LASTEXITCODE."
    }
    if (-not (Test-Path $plugin)) {
        throw "Application preview plugin was not produced: $plugin"
    }

    Write-Host ('==> Preview plugin ready in {0:N2}s' -f $timer.Elapsed.TotalSeconds)
    if ($BuildOnly) {
        Write-Host "Preview plugin ready: $plugin"
        return
    }

    $previewerValue = $androidProjectSharedConfig.Paths[('Previewer' + $Configuration + 'ExecutablePath')]
    if ([string]::IsNullOrWhiteSpace($previewerValue)) {
        throw "Preview.Executable.$Configuration must specify the AndroidAppPreviewer executable."
    }
    $previewer = if ([IO.Path]::IsPathRooted($previewerValue)) {
        [IO.Path]::GetFullPath($previewerValue)
    } else {
        [IO.Path]::GetFullPath((Join-Path $ProjectRoot $previewerValue))
    }
    if (-not (Test-Path -LiteralPath $previewer -PathType Leaf)) {
        throw "AndroidAppPreviewer executable was not found: $previewer"
    }

    Write-Host "==> Starting $previewer"
    Start-Process -FilePath $previewer -ArgumentList '--plugin', ('"{0}"' -f $plugin) -WindowStyle Normal
} catch {
    Write-Error $_
    exit 1
} finally {
    $env:ANDROID_BUILD_XAML_GENERATED_PROJECT = $previousGeneratedProject
}