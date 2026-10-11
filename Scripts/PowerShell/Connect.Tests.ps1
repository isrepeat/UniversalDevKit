param([string]$RepositoryPath = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'FormatXmlAttributes.ps1')
. (Join-Path $PSScriptRoot 'Modules/Module.Udk.Connection/Private/ConnectionPlan.ps1')

function AssertEqual($Actual, $Expected, [string]$Label) {
    if (($Actual -join ';') -cne ($Expected -join ';')) { throw "${Label}: expected $($Expected -join ';'), got $($Actual -join ';')" }
}
function AssertFails([scriptblock]$Action, [string]$Pattern) {
    try { & $Action | Out-Null } catch {
        if ($_.Exception.Message -notmatch $Pattern) { throw }
        return
    }
    throw "Expected failure: $Pattern"
}

# Проверяем перенос атрибутов, сохранение комментариев и повторное форматирование.
$xmlInput = '<Root><!-- <Node A="1" B="2" /> --><Node A="x > y" B="2" /></Root>'
$xmlFormatted = Format-UdkXmlAttributes $xmlInput
AssertEqual (Format-UdkXmlAttributes $xmlFormatted) $xmlFormatted 'XML formatting stability'
if (-not $xmlFormatted.Contains('<!-- <Node A="1" B="2" /> -->')) { throw 'XML comment changed' }
if ($xmlFormatted -notmatch 'A="x > y"\r?\n +B="2"') { throw 'XML attributes were not split' }
$null = [xml]$xmlFormatted

# Проверяем транзитивную DLL с внутренней статической зависимостью.
$componentRegistry = @{
    A = [pscustomobject]@{ Dependencies = @([pscustomobject]@{ Component = 'B'; Visibility = 'private'; Linkage = 'same' }) }
    B = [pscustomobject]@{ Dependencies = @([pscustomobject]@{ Component = 'C'; Visibility = 'private'; Linkage = 'static' }) }
    C = [pscustomobject]@{ Dependencies = @() }
}
$graph = Resolve-UdkLinkageGraph @('A') @{ A = 'Dynamic' } $componentRegistry
AssertEqual $graph.LinkComponents @('A') 'Private DLL link set'
AssertEqual $graph.RuntimeComponents @('A', 'B') 'Transitive runtime set'
AssertEqual $graph.DefinitionComponents @('A') 'Private import definitions'
AssertEqual $graph.ResolvedModes.C 'Static' 'Forced static dependency'

# Публичная DLL передаёт ссылку и import-макрос потребителю.
$componentRegistry.A.Dependencies[0].Visibility = 'public'
$graph = Resolve-UdkLinkageGraph @('A') @{ A = 'Dynamic' } $componentRegistry
AssertEqual $graph.LinkComponents @('A', 'B') 'Public DLL link set'
AssertEqual $graph.DefinitionComponents @('A', 'B') 'Public import definitions'
$graph = Resolve-UdkLinkageGraph @('A') @{ A = 'Static' } $componentRegistry
AssertEqual $graph.LinkComponents @('A', 'B', 'C') 'Static link closure'
AssertEqual $graph.RuntimeComponents @() 'Static runtime set'
$graph = Resolve-UdkLinkageGraph @('A') @{ A = 'Shared' } $componentRegistry
AssertEqual $graph.LinkComponents @() 'Shared link set'
AssertEqual @($graph.ResolvedModes.Values | Sort-Object -Unique) @('Shared') 'Shared closure'

# Конфликт вариантов и цикл обнаруживаются до изменения файлов.
AssertFails { Resolve-UdkLinkageGraph @('A', 'C') @{ A = 'Dynamic'; C = 'Dynamic' } $componentRegistry } 'Conflicting linkage for C'
AssertFails { Resolve-UdkLinkageGraph @('A', 'B') @{ A = 'Shared'; B = 'Static' } $componentRegistry } 'Conflicting linkage for B'
$componentRegistry.C.Dependencies = @([pscustomobject]@{ Component = 'A'; Visibility = 'private'; Linkage = 'same' })
AssertFails { Resolve-UdkLinkageGraph @('A') @{ A = 'Static' } $componentRegistry } 'dependency cycle'
$componentRegistry.C.Dependencies = @([pscustomobject]@{ Component = 'Missing'; Visibility = 'private'; Linkage = 'same' })
AssertFails { Resolve-UdkLinkageGraph @('A') @{ A = 'Static' } $componentRegistry } 'Unknown component'

# Проверяем реальный реестр компонентов и сохранение новых полей JSON.
Import-Module (Join-Path $PSScriptRoot 'Modules/Module.Udk.Connection/Module.Udk.Connection.psm1') -Force
$componentRegistry = Module.Udk.Connection\Get-UdkComponentRegistry $RepositoryPath
AssertEqual $componentRegistry.Diagnostic.Dependencies[0].Visibility 'private' 'ComponentRegistry visibility'
AssertEqual $componentRegistry.Diagnostic.Dependencies[0].Linkage 'static' 'ComponentRegistry linkage'
$request = [pscustomobject]@{ Components = @('Diagnostic'); ComponentModes = @{ Diagnostic = 'Dynamic' }; ProjectOnly = $false; Disconnect = $false }
$state = [pscustomobject]@{ Components = @(); Modes = @{} }
$plan = Module.Udk.Connection\New-UdkConnectionPlan $request $state $componentRegistry $RepositoryPath
AssertEqual $plan.LinkComponents @('Diagnostic') 'Diagnostic DLL link set'
AssertEqual $plan.RuntimeComponents @('Diagnostic') 'Diagnostic DLL runtime set'
$request.Disconnect = $true
$request.Components = @()
$plan = Module.Udk.Connection\New-UdkConnectionPlan $request $state $componentRegistry $RepositoryPath
AssertEqual $plan.LinkComponents @() 'Disconnect link set'
# Меню учитывает существующие подключения, переключение режима и удаление корней.
. (Join-Path $PSScriptRoot 'Modules/Module.Udk.Console/Private/Menus.ps1')
$conflict = Get-UdkMenuModeConflict @{ Diagnostic = 'Dynamic' } @{} $componentRegistry -Name Helpers -Mode Dynamic
if ($conflict -notmatch 'Conflicting linkage for Helpers') { throw 'Menu did not block Helpers.Dynamic' }
$conflict = Get-UdkMenuModeConflict @{ Diagnostic = 'Dynamic' } @{} $componentRegistry -Name Helpers -Mode Static
if ($conflict) { throw "Menu blocked compatible Static: $conflict" }
$conflict = Get-UdkMenuModeConflict @{ Helpers = 'Shared' } @{ Helpers = 'Static' } $componentRegistry -Name Diagnostic -Mode Dynamic
if ($conflict) { throw "Menu ignored the pending mode change: $conflict" }
$conflict = Get-UdkMenuModeConflict @{} @{} $componentRegistry -Name Helpers -Mode Dynamic -ProjectOnly
if ($conflict -notmatch 'requires SolutionPath') { throw 'Menu did not block binary ProjectOnly mode' }
$conflict = Get-UdkMenuModeConflict @{ Diagnostic = 'Dynamic'; Helpers = 'Dynamic' } @{ Helpers = 'Dynamic' } $componentRegistry -Removal
if ($conflict) { throw "Menu blocked removal that resolves conflict: $conflict" }
Write-Output 'Connect dependency and menu validation tests passed.'