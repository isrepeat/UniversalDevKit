[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ProjectRoot,
    [string]$XamlCompiler)

$ErrorActionPreference = 'Stop'
Import-Module -Name (Join-Path $PSScriptRoot 'Modules\Module.AndroidBuildTools\Module.AndroidBuildTools.psm1') -ErrorAction Stop
Module.AndroidBuildTools\Initialize-AndroidBuildConsole
$androidProjectConfig = Module.AndroidBuildTools\Read-AndroidBuildConfiguration $ProjectRoot
$androidProjectSharedConfig = Module.AndroidBuildTools\Read-AndroidBuildSharedConfiguration $ProjectRoot
if (-not $androidProjectConfig.Xaml) {
    return
}

$applicationRoot = Join-Path $projectRoot $androidProjectConfig.Application
$uiRoot = Join-Path $projectRoot $androidProjectConfig.UI
$xamlSourceRoots = @(
    @{
        Source = Join-Path $applicationRoot 'UI'
        Generated = Join-Path $projectRoot "!Generated\$($androidProjectConfig.Application)\Xaml"
    },
    @{
        Source = $uiRoot
        Generated = Join-Path $projectRoot "!Generated\$($androidProjectConfig.UI)\Xaml"
    }
)
$xamlIgnoreConfigurationPath = Join-Path $applicationRoot 'UI\XamlCompilerIgnore.json'
$xamlIgnoreConfiguration = Get-Content -LiteralPath $xamlIgnoreConfigurationPath -Raw | ConvertFrom-Json
$xamlIgnoredDirectories = @($xamlIgnoreConfiguration.directories)
$xamlIgnoredFileSuffixes = @($xamlIgnoreConfiguration.fileSuffixes)

function Invoke-Checked {
    param(
        [Parameter(Mandatory)] [string]$Program,
        [Parameter(Mandatory)] [string[]]$Arguments
    )

    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code ${LASTEXITCODE}: $Program $($Arguments -join ' ')"
    }
}

$xamlPackagesRoot = Module.AndroidBuildTools\Resolve-AndroidBuildConfigurationPath -Configuration $androidProjectConfig -ProjectRoot $ProjectRoot -Name 'PackageDirectories.XamlRuntime'
$nativePackageSource = $androidProjectSharedConfig.Paths.PackagesFeed
if (-not $XamlCompiler) {
    $XamlCompiler = Module.AndroidBuildTools\Resolve-XamlCompiler -PackagesRoot $xamlPackagesRoot -Source $nativePackageSource
}
if (-not (Test-Path -LiteralPath $XamlCompiler -PathType Leaf)) { throw "XamlCompiler was not found: $XamlCompiler" }
Write-Host "==> Using XamlCompiler from $xamlCompiler"

foreach ($xamlSourceRoot in $xamlSourceRoots) {
    Get-ChildItem -LiteralPath $xamlSourceRoot.Source -Filter '*.xaml' -File -Recurse | ForEach-Object {
        $relativePath = $_.FullName.Substring($xamlSourceRoot.Source.Length).TrimStart('\', '/')
        $generatedPath = Join-Path $xamlSourceRoot.Generated ($relativePath + '.cpp')
        $generatedHeaderPath = [System.IO.Path]::ChangeExtension($generatedPath, '.h')
        $generatedFiles = @($generatedPath, $generatedHeaderPath)
        $generationInputs = @($_.FullName, $xamlCompiler, $xamlIgnoreConfigurationPath)
        $requiresGeneration = $generatedFiles | Where-Object { -not (Test-Path $_) }
        if ($null -eq $requiresGeneration) {
            $oldestGeneratedFile = Get-Item -LiteralPath $generatedFiles | Sort-Object LastWriteTimeUtc | Select-Object -First 1
            $requiresGeneration = $generationInputs | Where-Object {
                (Get-Item -LiteralPath $_).LastWriteTimeUtc -gt $oldestGeneratedFile.LastWriteTimeUtc
            }
        }
        if ($null -ne $requiresGeneration) {
            $compilerArguments = @(
                $_.FullName,
                $generatedPath,
                '--xaml-namespace',
                $androidProjectConfig.Xaml.Namespace,
                '--control-xml-prefix',
                'control',
                '--control-cpp-namespace',
                $androidProjectConfig.Xaml.ControlNamespace,
                '--control-include-prefix',
                $androidProjectConfig.Xaml.ControlIncludePrefix
            )
            foreach ($directory in $xamlIgnoredDirectories) {
                $compilerArguments += '--ignore-directory', $directory
            }
            foreach ($suffix in $xamlIgnoredFileSuffixes) {
                $compilerArguments += '--ignore-file-suffix', $suffix
            }
            Write-Host "==> Compiling $($_.Name) into native UI classes"
            Invoke-Checked $xamlCompiler $compilerArguments
        }
    }
}