param()
$env:DOTNET_CLI_UI_LANGUAGE = 'en-US'
$env:VSLANG = '1033'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)
$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repository 'Scripts/PowerShell/ArtifactDirectories.ps1')
$run = Reset-UdkArtifactDirectory -Root (Join-Path $repository '!artifacts/tests') -Path (Join-Path $repository '!artifacts/tests/TestRuntimeCleanup')
$sources = Join-Path $run 'sources'
$output = Join-Path $run 'output'
[void][IO.Directory]::CreateDirectory($sources)
[void][IO.Directory]::CreateDirectory($output)
$list = Join-Path $run 'sources.txt'
$sync = Join-Path $repository 'Scripts/PowerShell/SyncRuntimeLibraries.ps1'
$dll = Join-Path $sources 'Probe.dll'
[IO.File]::WriteAllBytes($dll, [byte[]]@(1, 2, 3))
function Deliver([string]$Owner, [string[]]$Files) {
    [IO.File]::WriteAllLines($list, $Files, [Text.UTF8Encoding]::new($false))
    & $sync -OutputDirectory $output -Owner $Owner -SourceList $list
}
function AssertExists([string]$Name, [bool]$Expected) {
    if ((Test-Path -LiteralPath (Join-Path $output $Name)) -ne $Expected) { throw "Unexpected file state: $Name" }
}
# Повторная доставка, общий OutDir и снятие последнего владельца.
Deliver 'App1|Debug|x64' @($dll)
Deliver 'App1|Debug|x64' @($dll)
Deliver 'App2|Debug|x64' @($dll)
Deliver 'App1|Debug|x64' @()
AssertExists 'Probe.dll' $true
Deliver 'App2|Debug|x64' @()
AssertExists 'Probe.dll' $false
# Ручные изменения не удаляются, даже после Disconnect.
Deliver 'App1|Debug|x64' @($dll)
[IO.File]::WriteAllBytes((Join-Path $output 'Probe.dll'), [byte[]]@(4, 5))
Deliver 'App1|Debug|x64' @()
AssertExists 'Probe.dll' $true
# Идентичный файл, размещённый вручную, также не становится собственностью UDK.
$manual = Join-Path $sources 'Manual.dll'
[IO.File]::WriteAllBytes($manual, [byte[]]@(8, 9))
Copy-Item -LiteralPath $manual -Destination $output
Deliver 'App1|Debug|x64' @($manual)
Deliver 'App1|Debug|x64' @($manual)
Deliver 'App1|Debug|x64' @()
AssertExists 'Manual.dll' $true
# Несовместимые копии в общем OutDir отклоняются до перезаписи.
$other = Join-Path $sources 'Other.dll'
[IO.File]::WriteAllBytes($other, [byte[]]@(7, 8))
Deliver 'App1|Debug|x64' @($other)
[IO.File]::WriteAllBytes($other, [byte[]]@(9, 10))
$failed = $false
try { Deliver 'App2|Debug|x64' @($other) } catch { $failed = $_.Exception.Message -like 'Another consumer requires*' }
if (-not $failed) { throw 'Conflicting owners were not rejected.' }
if ((Get-FileHash -LiteralPath (Join-Path $output 'Other.dll')).Hash -eq (Get-FileHash -LiteralPath $other).Hash) { throw 'Conflicting DLL was overwritten.' }
# Проверяем настоящий target: доставка DLL и повторный Build с пустым runtime-набором.
. (Join-Path $PSScriptRoot 'BuildTools.ps1')
$msbuild = Get-TestMSBuild
$project = Join-Path $repository 'Tests/Fixtures/RuntimeCleanup/Consumer.proj'
$buildOutput = Join-Path $run 'msbuild-output'
$intermediate = Join-Path $run 'obj'
foreach ($deliver in @('true', 'false')) {
    & $msbuild $project /nologo /v:minimal "/p:Deliver=$deliver" "/p:RuntimeSource=$dll" "/p:OutDir=$buildOutput/" "/p:IntDir=$intermediate/"
    if ($LASTEXITCODE -ne 0) { throw 'Runtime target test failed.' }
    if ((Test-Path -LiteralPath (Join-Path $buildOutput 'Probe.dll')) -ne ($deliver -eq 'true')) { throw 'Runtime target did not synchronize DLLs.' }
}
Write-Output "Runtime cleanup tests passed: $run"