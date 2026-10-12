param($Workspace, [string]$MSBuild, [string]$SolutionInjectorPath)
Test-ComponentConnection $Workspace $MSBuild $SolutionInjectorPath Shared
$arguments = @{
    SolutionPath = Join-Path $Workspace.Consumer 'Consumer.sln'
    ProjectPath = Join-Path $Workspace.Consumer 'App1/App1.vcxproj'
    Components = @('Helpers', 'Diagnostic')
    Disconnect = $true
}
if ($SolutionInjectorPath) { $arguments.SolutionInjectorPath = $SolutionInjectorPath }
& (Join-Path $Workspace.Library 'Scripts/PowerShell/Connect.ps1') @arguments | Out-Host
[xml]$project = [IO.File]::ReadAllText($arguments.ProjectPath)
if ($project.SelectNodes('//*[@Label="UniversalDevKit"]').Count -or $project.OuterXml -match 'UniversalDevKit\.(Helpers|Diagnostic)\.(Shared|Static|Dynamic)') {
    throw 'Disconnect left UDK integration in App1.'
}
# Отключённый App1 требует UDK в исходниках и больше не должен собираться; соседний App2 независим.
foreach ($configuration in @('Debug', 'Release')) {
    Invoke-TestBuild $MSBuild (Join-Path $Workspace.Consumer 'App2/App2.vcxproj') $configuration (Join-Path $Workspace.Root 'logs/Disconnect')
    Invoke-TestApplication (Join-Path $Workspace.Consumer "!artifacts/x64/$configuration/App2/bin/App2.exe") 'App2 passed'
}