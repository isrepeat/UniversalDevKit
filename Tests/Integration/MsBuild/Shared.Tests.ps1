param($Workspace, [string]$MSBuild, [string]$SolutionInjectorPath)
$env:DOTNET_CLI_UI_LANGUAGE = 'en-US'
$env:VSLANG = '1033'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)

Test-ComponentConnection $Workspace $MSBuild $SolutionInjectorPath Shared