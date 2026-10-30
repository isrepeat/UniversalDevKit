param()

$ErrorActionPreference = 'Stop'
$env:DOTNET_CLI_UI_LANGUAGE = 'en-US'
$env:VSLANG = '1033'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)
$repository = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$loader = Join-Path $repository 'Scripts/PowerShell/GetNuGet.ps1'
$tool = & $loader
$firstWrite = (Get-Item -LiteralPath $tool).LastWriteTimeUtc
if ((& $loader) -ne $tool -or (Get-Item -LiteralPath $tool).LastWriteTimeUtc -ne $firstWrite) {
    throw 'Cached NuGet was not reused.'
}
if ((& $loader -LocalPath $tool) -ne $tool) { throw 'Explicit NuGet path was not preserved.' }
& $tool help | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'NuGet could not run.' }

# Проверяем повреждённый кеш в изолированном каталоге, не меняя рабочий инструмент.
$run = Join-Path $repository ('!artifacts/tests/tools-' + [Guid]::NewGuid().ToString('N'))
$scripts = Join-Path $run 'Scripts/PowerShell'
$manifests = Join-Path $run 'Scripts/Tools'
[void][IO.Directory]::CreateDirectory($scripts)
[void][IO.Directory]::CreateDirectory($manifests)
Copy-Item -LiteralPath $loader -Destination $scripts
Copy-Item -LiteralPath (Join-Path $repository 'Scripts/Tools/NuGet.json') -Destination $manifests
$manifest = Get-Content -LiteralPath (Join-Path $manifests 'NuGet.json') -Raw | ConvertFrom-Json
$cache = Join-Path $run ('!tools/NuGet/' + $manifest.version)
[void][IO.Directory]::CreateDirectory($cache)
$corrupt = Join-Path $cache 'nuget.exe'
[IO.File]::WriteAllBytes($corrupt, [byte[]]@(0, 1, 2))
$rejected = $false
try { & (Join-Path $scripts 'GetNuGet.ps1') | Out-Null }
catch {
    if ($_.Exception.Message -notlike 'Cached NuGet executable SHA-256 mismatch:*') { throw }
    $rejected = $true
}
if (-not $rejected) { throw 'Corrupt NuGet cache was accepted.' }
if ((Get-Item -LiteralPath $corrupt).Length -ne 3) { throw 'Corrupt cache was unexpectedly overwritten.' }
Write-Host 'PASS: NuGet execution, cache reuse, explicit path and corrupt cache rejection.'