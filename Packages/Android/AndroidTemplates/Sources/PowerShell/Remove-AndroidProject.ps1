[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ProjectRoot,

    [switch]$Confirmed,

    [string]$SigningProperties,

    [string]$SecretsRoot
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath($ProjectRoot)
$configurationPath = Join-Path $projectRoot 'android-build.psd1'
if (-not (Test-Path -LiteralPath $configurationPath -PathType Leaf)) {
    throw "Project configuration was not found: $configurationPath"
}

$configuration = Import-PowerShellDataFile -LiteralPath $configurationPath
if (-not $SecretsRoot) {
    . (Join-Path $PSScriptRoot 'Read-AndroidSharedProps.ps1')
    $sharedProps = Read-AndroidSharedProps -ProjectRoot $projectRoot
    $SecretsRoot = $sharedProps.Paths.SecretsRoot
}

# У старых проектов package ID читаем из Gradle; новые сохраняют его в конфигурации.
$packageId = $configuration.PackageId
if (-not $packageId) {
    $gradlePath = Join-Path $projectRoot "$($configuration.AndroidModule)\build.gradle.kts"
    $packageMatch = [System.Text.RegularExpressions.Regex]::Match([System.IO.File]::ReadAllText($gradlePath), 'applicationId\s*=\s*"([a-z][a-z0-9]*(?:\.[a-z][a-z0-9]*)+)"')
    $packageId = $packageMatch.Groups[1].Value
}
if ($packageId -notmatch '^[a-z][a-z0-9]*(\.[a-z][a-z0-9]*)+$') {
    throw 'A valid project PackageId is required to remove project secrets.'
}
# Удаляем только непосредственный каталог пакета внутри SecretsRoot, никогда shared.
$secretsRootPath = [System.IO.Path]::GetFullPath($SecretsRoot).TrimEnd('\', '/')
$secretsDirectory = [System.IO.Path]::GetFullPath((Join-Path $secretsRootPath $packageId))
if ([System.IO.Path]::GetDirectoryName($secretsDirectory) -ne $secretsRootPath -or $secretsDirectory -eq $projectRoot -or $projectRoot.StartsWith($secretsDirectory + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Invalid project secrets directory: $secretsDirectory"
}
if (-not $Confirmed) {
    $description = "Delete project and secrets for $packageId (shared signing keys are preserved)? [Y/N]"
    $answer = Read-Host $description
    if ($answer -ine 'Y') {
        Write-Host 'Deletion cancelled.'
        return
    }
}

$normalizedProjectRoot = $projectRoot.TrimEnd('\') + '\'
$scriptPath = [IO.Path]::GetFullPath($PSCommandPath)
if ($scriptPath.StartsWith($normalizedProjectRoot, [StringComparison]::OrdinalIgnoreCase)) {
    $temporaryScript = Join-Path ([IO.Path]::GetTempPath()) ("Remove-AndroidProject-{0}.ps1" -f [Guid]::NewGuid().ToString('N'))
    Copy-Item -LiteralPath $scriptPath -Destination $temporaryScript -Force
    try {
        & $temporaryScript -ProjectRoot $projectRoot -Confirmed -SecretsRoot $secretsRootPath
        exit $LASTEXITCODE
    } finally {
        Remove-Item -LiteralPath $temporaryScript -Force -ErrorAction SilentlyContinue
    }
}

Set-Location -LiteralPath ([IO.Path]::GetTempPath())
if (Test-Path -LiteralPath $secretsDirectory -PathType Container) {
    Write-Host "Removing secrets: $secretsDirectory"
    Remove-Item -LiteralPath $secretsDirectory -Recurse -Force
}
Write-Host "Removing project: $projectRoot"
Remove-Item -LiteralPath $projectRoot -Recurse -Force