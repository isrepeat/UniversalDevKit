$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../../FormatXmlAttributes.ps1')
. (Join-Path $PSScriptRoot 'Private/Requirements.ps1')

. (Join-Path $PSScriptRoot 'Private/ComponentRegistry.ps1')
. (Join-Path $PSScriptRoot 'Private/ConnectionState.ps1')
. (Join-Path $PSScriptRoot 'Private/ConnectionPlan.ps1')
. (Join-Path $PSScriptRoot 'Private/SolutionIntegration.ps1')
. (Join-Path $PSScriptRoot 'Private/ProjectIntegration.ps1')

Export-ModuleMember -Function @(
    'Get-UdkComponentRegistry'
    'Resolve-UdkComponents'
    'Get-UdkConnectionState'
    'New-UdkConnectionPlan'
    'Invoke-UdkConnectionPlan'
)