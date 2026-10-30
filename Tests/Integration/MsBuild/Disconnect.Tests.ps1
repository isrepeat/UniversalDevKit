param($Workspace, [string]$MSBuild, [string]$SolutionInjectorPath)
$env:DOTNET_CLI_UI_LANGUAGE = 'en-US'
$env:VSLANG = '1033'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)

Test-ComponentConnection $Workspace $MSBuild $SolutionInjectorPath Shared
$arguments = @{
    SolutionPath = Join-Path $Workspace.Consumer 'Consumer.sln'
    ProjectPath = Join-Path $Workspace.Consumer 'App1/App1.vcxproj'
    Components = @('HeleprsTest', 'DiagnosticTest')
    Disconnect = $true
}
if ($SolutionInjectorPath) { $arguments.SolutionInjectorPath = $SolutionInjectorPath }
& (Join-Path $Workspace.Library 'Scripts/PowerShell/Connect.ps1') @arguments | Out-Host
[xml]$project = [IO.File]::ReadAllText($arguments.ProjectPath)
if ($project.SelectNodes('//*[@Label="UniversalDevKit"]').Count -or $project.OuterXml -match 'UniversalDevKit\.(HeleprsTest|DiagnosticTest)\.(Shared|Static|Dynamic)') {
    throw 'Disconnect left UDK integration in App1.'
}
# Disconnected App1 requires UDK and must fail to build; App2 remains independent.
foreach ($configuration in @('Debug', 'Release')) {
    Invoke-TestBuild $MSBuild (Join-Path $Workspace.Consumer 'App2/App2.vcxproj') $configuration (Join-Path $Workspace.Root 'logs/Disconnect')
    Invoke-TestApplication (Join-Path $Workspace.Consumer "!artifacts/x64/$configuration/App2/bin/App2.exe") 'App2 passed'
}