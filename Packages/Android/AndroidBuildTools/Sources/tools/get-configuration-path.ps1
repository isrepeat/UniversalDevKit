[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ProjectRoot,

    [Parameter(Mandatory)]
    [string]$Name
)

$ErrorActionPreference = 'Stop'

Import-Module -Name (Join-Path $PSScriptRoot 'Modules\Module.AndroidBuildTools\Module.AndroidBuildTools.psm1') -ErrorAction Stop
Module.AndroidBuildTools\Initialize-AndroidBuildConsole
$androidProjectConfig = Module.AndroidBuildTools\Read-AndroidBuildConfiguration $ProjectRoot
Module.AndroidBuildTools\Resolve-AndroidBuildConfigurationPath -Configuration $androidProjectConfig -ProjectRoot $ProjectRoot -Name $Name