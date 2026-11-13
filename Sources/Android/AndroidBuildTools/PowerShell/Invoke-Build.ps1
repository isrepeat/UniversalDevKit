[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ProjectRoot,

    [Parameter(Position = 0)]
    [ValidateSet('restore', 'get-configuration-path', 'get-configuration-value', 'build-android', 'build-and-distribute', 'build-for-drive', 'build-all', 'bump-version', 'generate-xaml', 'upload-apk-to-drive', 'run-android-app-previewer')]
    [string]$Command = 'build-android',

    [ValidateSet('Debug', 'Release')]
    [string]$Configuration,
    [ValidateSet('arm64-v8a')]
    [string]$Architecture,
    [ValidateSet('Local', 'Drive')]
    [string]$Destination,
    [switch]$Clean,
    [switch]$NativeOnly,
    [switch]$KeepVersion,
    [int]$AppVersionCode,
    [string]$AppVersionName,
    [string]$SigningProperties,
    [string]$TargetsConfigUrl,
    [string]$Name,
    [string]$ApkPath,
    [string]$FilePath,
    [string]$MimeType,
    [string]$OAuthClientPath,
    [string]$TokenPath,
    [string[]]$DrivePath,
    [string]$DriveFileName,
    [int]$ParentProcessId,
    [switch]$BuildOnly
)

$ErrorActionPreference = 'Stop'

# These settings are specific to the application. The package reads module names,
# resource paths, and secrets from the consumer's android-build.psd1.
Import-Module -Name (Join-Path $PSScriptRoot 'Modules\Module.AndroidBuildTools\Module.AndroidBuildTools.psm1') -ErrorAction Stop
Module.AndroidBuildTools\Initialize-AndroidBuildConsole
$androidProjectConfig = Module.AndroidBuildTools\Read-AndroidBuildConfiguration $ProjectRoot
$androidProjectSharedConfig = Module.AndroidBuildTools\Read-AndroidBuildSharedConfiguration $ProjectRoot

# $PSScriptRoot points to <package>/tools. Go up one level to find
# the other scripts and return the package root for restore.
$packageRoot = Split-Path -Parent $PSScriptRoot

# $PSBoundParameters contains only arguments explicitly provided by the caller.
# Collect them in a separate table for the downstream script.
# Command selects the action, and ProjectRoot is added below.
# Keep both out of the downstream parameter table.
$parameters = @{}
foreach ($name in $PSBoundParameters.Keys) {
    if ($name -notin @('Command', 'ProjectRoot')) {
        $parameters[$name] = $PSBoundParameters[$name]
    }
}

# restore is used by CMake and Gradle. It returns only the restored package path
# so they can load the CMake modules or Gradle plugins.
# Other parameters are invalid in this mode.
if ($Command -eq 'restore') {
    if ($parameters.Count -gt 0) {
        throw 'The restore command does not accept build parameters.'
    }
    return $packageRoot
}

# Keep these two names as shortcuts for .bat files. One command handles
# building the versioned APK and uploading it to Google Drive.
if ($Command -in @('build-for-drive', 'build-all')) {
    $Command = 'build-and-distribute'
    $parameters.Destination = 'Drive'
}

# The command name matches its filename under tools.
# For example, build-android maps to tools/build-android.ps1.
$script = Join-Path $packageRoot "tools\$Command.ps1"
if ($Command -eq 'upload-apk-to-drive' -and $parameters.ContainsKey('ApkPath')) {
    if ($parameters.ContainsKey('FilePath')) {
        throw 'Specify either ApkPath or FilePath, not both.'
    }
    $parameters.FilePath = $parameters.ApkPath
    $parameters.Remove('ApkPath')
}

# Read the selected script's contract before passing arguments
# so unsupported parameters are caught at the call site.
$metadata = Get-Command -Name $script -ErrorAction Stop
foreach ($name in $parameters.Keys) {
    if (-not $metadata.Parameters.ContainsKey($name)) {
        throw "The $Command command does not accept -$name."
    }
}

# upload-apk-to-drive takes an APK and Google Drive credentials without ProjectRoot.
# If the command line omits OAuth and Drive paths, use the Drive section
# of the application configuration.
if ($Command -eq 'upload-apk-to-drive') {
    foreach ($name in @('OAuthClientPath', 'TokenPath')) {
        if (-not $parameters.ContainsKey($name)) {
            $parameters[$name] = $androidProjectSharedConfig.Paths[('Drive' + $name)]
        }
    }
    if (-not $parameters.ContainsKey('DrivePath')) {
        $parameters.DrivePath = $androidProjectConfig.Drive.Path
    }
} else {
    # Other commands work with the project and always receive its root,
    # even when the caller omits -ProjectRoot.
    $parameters.ProjectRoot = $ProjectRoot
}

# Use the & operator to invoke the PowerShell script. @parameters splats
# the hashtable into named arguments. For example, Configuration = 'Debug'
# becomes -Configuration Debug.
& $script @parameters