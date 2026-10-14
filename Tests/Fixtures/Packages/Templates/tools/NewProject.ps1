param([Parameter(Mandatory = $true)][string]$Destination)
$env:DOTNET_CLI_UI_LANGUAGE = 'en-US'
$env:VSLANG = '1033'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)

$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath $Destination) { throw 'Destination must not exist.' }
[void][IO.Directory]::CreateDirectory($Destination)
Copy-Item -Path (Join-Path $PSScriptRoot '../template/*') -Destination $Destination