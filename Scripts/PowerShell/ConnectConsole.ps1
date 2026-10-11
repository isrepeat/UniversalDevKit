param(
    [string]$ProjectPath,
    [string[]]$Components,
    [hashtable]$ComponentModes = @{},
    [string]$SolutionPath,
    [string]$SolutionInjectorPath,
    [switch]$ProjectOnly,
    [switch]$Disconnect
)

$ErrorActionPreference = 'Stop'
$exitCode = 0
try {
    # Выполняем Connect в текущей области, чтобы итог использовал ту же палитру.
    . (Join-Path $PSScriptRoot 'Connect.ps1') @PSBoundParameters
    WriteMenuText 'Completed successfully.' Mark
}
catch {
    $exitCode = 1
    if (Get-Command WriteMenuText -ErrorAction SilentlyContinue) {
        WriteMenuText ('Failed: ' + $_.Exception.Message) Focus
    }
    else { Write-Host ('Failed: ' + $_.Exception.Message) -ForegroundColor Yellow }
}

if (Get-Command WriteMenuText -ErrorAction SilentlyContinue) {
    WriteMenuText 'Press any key to continue...' Hint
}
exit $exitCode