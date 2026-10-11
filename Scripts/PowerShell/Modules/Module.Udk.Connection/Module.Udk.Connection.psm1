$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Private/ComponentCatalog.ps1')
. (Join-Path $PSScriptRoot 'Private/ConnectionState.ps1')
. (Join-Path $PSScriptRoot 'Private/ConnectionPlan.ps1')
. (Join-Path $PSScriptRoot 'Private/SolutionIntegration.ps1')
. (Join-Path $PSScriptRoot 'Private/ProjectIntegration.ps1')

Export-ModuleMember -Function @(
    'Get-UdkComponentCatalog'
    'Resolve-UdkComponents'
    'Get-UdkConnectionState'
    'New-UdkConnectionPlan'
    'Invoke-UdkConnectionPlan'
)