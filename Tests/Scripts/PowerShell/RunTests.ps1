param(
    [ValidateSet('WorkingTree', 'Submodule')][string]$Mode = 'WorkingTree',
    [string]$Revision = 'HEAD',
    [string]$SolutionInjectorPath,
    [switch]$CleanOnSuccess,
    [ValidateSet('Shared', 'Static', 'Dynamic', 'ModeSwitch', 'Disconnect', 'Diamond', 'Export', 'Runtime')]
    [string[]]$Scenario = @('Shared', 'Static', 'Dynamic', 'ModeSwitch', 'Disconnect', 'Diamond', 'Export', 'Runtime')
)

$env:DOTNET_CLI_UI_LANGUAGE = 'en-US'
$env:VSLANG = '1033'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)

$ErrorActionPreference = 'Stop'
$testsPath = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$repositoryPath = Split-Path -Parent $testsPath
. (Join-Path $repositoryPath 'Scripts/PowerShell/ArtifactDirectories.ps1')
$reportDirectory = Reset-UdkArtifactDirectory -Root (Join-Path $repositoryPath '!artifacts/tests') -Path (Join-Path $repositoryPath '!artifacts/tests/RunTests')
[void][IO.Directory]::CreateDirectory($reportDirectory)
$transcriptPath = Join-Path $reportDirectory 'console.log'
$summaryPath = Join-Path $reportDirectory 'summary.csv'
$selectedScenarios = @($Scenario | Select-Object -Unique)
$results = @('Setup', 'PublicHeaders', 'Shared', 'Static', 'Dynamic', 'ModeSwitch', 'Disconnect', 'Diamond', 'Export', 'Runtime') | ForEach-Object {
    [pscustomobject]@{
        Test = $_
        Status = if ($_ -in @('Setup', 'PublicHeaders') -or $_ -in $selectedScenarios) { 'NotRun' } else { 'NotSelected' }
        Mode = $Mode
        Started = ''
        Finished = ''
        Workspace = ''
        Error = ''
    }
}
function Save-TestReport {
    # Persist progress after every transition, including tests not reached after a failure.
    $results | Export-Csv -LiteralPath $summaryPath -NoTypeInformation -Encoding UTF8
}
function Start-TestRecord([string]$Name) {
    $record = $results | Where-Object Test -eq $Name
    $record.Status = 'Running'
    $record.Started = (Get-Date).ToString('o')
    Save-TestReport
    return $record
}
function Complete-TestRecord($Record) {
    $Record.Status = 'Passed'
    $Record.Finished = (Get-Date).ToString('o')
    Save-TestReport
}
$workspace = $null
$currentRecord = $null
$exitCode = 1
$transcriptStarted = $false
try {
    Start-Transcript -LiteralPath $transcriptPath -Force | Out-Host
    $transcriptStarted = $true
    Write-Host "Test reports: $reportDirectory"
    $currentRecord = Start-TestRecord 'Setup'
    . (Join-Path $testsPath 'Infrastructure/TestWorkspace.ps1')
    . (Join-Path $testsPath 'Infrastructure/BuildTools.ps1')
    . (Join-Path $testsPath 'Integration/MsBuild/Connect.Tests.ps1')
    $msbuild = Get-TestMSBuild
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'Git is required.' }
    Complete-TestRecord $currentRecord
    $currentRecord = Start-TestRecord 'PublicHeaders'
    & (Join-Path $testsPath 'Infrastructure/TestPublicHeaders.ps1') -RepositoryPath $repositoryPath
    Complete-TestRecord $currentRecord
    foreach ($name in $selectedScenarios) {
        $currentRecord = Start-TestRecord $name
        $workspace = $null
        $workspace = New-TestWorkspace $repositoryPath $Mode $Revision -Name $name
        $currentRecord.Workspace = $workspace.Root
        Save-TestReport
        Write-Host "Scenario: $name; workspace: $($workspace.Root)"
        # Each scenario uses its own consumer and library copy.
        & (Join-Path $testsPath "Integration/MsBuild/$name.Tests.ps1") $workspace $msbuild $SolutionInjectorPath
        Write-Host "PASS: $name ($Mode), Debug/Release x64."
        if ($CleanOnSuccess) { Remove-TestWorkspace $repositoryPath $workspace }
        Complete-TestRecord $currentRecord
    }
    $exitCode = 0
}
catch {
    if ($currentRecord) {
        $currentRecord.Status = 'Failed'
        $currentRecord.Finished = (Get-Date).ToString('o')
        $currentRecord.Error = $_.Exception.Message
    }
    Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace
    if ($workspace) { Write-Host "Preserved workspace: $($workspace.Root)" }
}
finally {
    Save-TestReport
    Write-Host ($results | Format-Table Test, Status, Workspace -AutoSize | Out-String)
    Write-Host "Summary: $summaryPath"
    Write-Host "Full console log: $transcriptPath"
    if ($transcriptStarted) { Stop-Transcript | Out-Host }
}
exit $exitCode