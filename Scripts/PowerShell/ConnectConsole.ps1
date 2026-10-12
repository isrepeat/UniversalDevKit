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
    Import-Module (Join-Path $PSScriptRoot 'Modules/Module.Udk.Console/Module.Udk.Console.psm1') -ErrorAction Stop
    & (Join-Path $PSScriptRoot 'Connect.ps1') @PSBoundParameters
    Module.Udk.Console\Write-UdkConsoleText 'Completed successfully.' Mark
}
catch {
    $exitCode = 1
    if (Get-Command Module.Udk.Console\Write-UdkConsoleText -ErrorAction SilentlyContinue) {
        Module.Udk.Console\Write-UdkConsoleText ('Failed: ' + $_.Exception.Message) Focus
    }
    else {
        Write-Host ('Failed: ' + $_.Exception.Message) -ForegroundColor Yellow
    }
}

if (Get-Command Module.Udk.Console\Write-UdkConsoleText -ErrorAction SilentlyContinue) {
    Module.Udk.Console\Write-UdkConsoleText 'Press any key to continue...' Hint
}
exit $exitCode