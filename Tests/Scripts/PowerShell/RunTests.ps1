param(
    [ValidateSet('WorkingTree', 'Submodule')][string]$Mode = 'WorkingTree',
    [string]$Revision = 'HEAD',
    [string]$SolutionInjectorPath,
    [switch]$CleanOnSuccess,
    [ValidateSet('Shared', 'Static', 'Dynamic', 'ModeSwitch', 'Disconnect', 'Diamond', 'Export', 'Runtime')]
    [string[]]$Scenario = @('Shared', 'Static', 'Dynamic', 'ModeSwitch', 'Disconnect', 'Diamond', 'Export', 'Runtime')
)

$ErrorActionPreference = 'Stop'
$testsPath = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$repositoryPath = Split-Path -Parent $testsPath
. (Join-Path $testsPath 'Infrastructure/TestWorkspace.ps1')
. (Join-Path $testsPath 'Infrastructure/BuildTools.ps1')
. (Join-Path $testsPath 'Integration/MsBuild/Connect.Tests.ps1')
$workspace = $null
try {
    $msbuild = Get-TestMSBuild
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'Git is required.' }
    & (Join-Path $testsPath 'Infrastructure/TestPublicHeaders.ps1') -RepositoryPath $repositoryPath
    foreach ($name in ($Scenario | Select-Object -Unique)) {
        $workspace = New-TestWorkspace $repositoryPath $Mode $Revision
        Write-Host "Scenario: $name; workspace: $($workspace.Root)"
        # Each scenario uses its own consumer and library copy.
        & (Join-Path $testsPath "Integration/MsBuild/$name.Tests.ps1") $workspace $msbuild $SolutionInjectorPath
        Write-Host "PASS: $name ($Mode), Debug/Release x64."
        if ($CleanOnSuccess) { Remove-TestWorkspace $repositoryPath $workspace }
    }
    exit 0
}
catch {
    Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
    if ($workspace) { Write-Host "Preserved workspace: $($workspace.Root)" }
    exit 1
}