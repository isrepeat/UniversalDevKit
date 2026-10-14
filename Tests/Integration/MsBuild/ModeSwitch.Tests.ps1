param($Workspace, [string]$MSBuild, [string]$SolutionInjectorPath)
# Each transition invokes real Connect and verifies the build and execution.
$env:DOTNET_CLI_UI_LANGUAGE = 'en-US'
$env:VSLANG = '1033'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)

foreach ($linkage in @('Shared', 'Static', 'Dynamic', 'Shared')) {
    Test-ComponentConnection $Workspace $MSBuild $SolutionInjectorPath $linkage
}