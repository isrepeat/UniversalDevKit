param([string]$LocalPath)

$ErrorActionPreference = 'Stop'
$env:DOTNET_CLI_UI_LANGUAGE = 'en-US'
$env:VSLANG = '1033'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)
$repository = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

if ($LocalPath -and $LocalPath -ne 'nuget.exe') {
    return (Get-Command $LocalPath -CommandType Application -ErrorAction Stop).Source
}

$manifest = Get-Content -LiteralPath (Join-Path $repository 'Scripts/Tools/NuGet.json') -Raw | ConvertFrom-Json
$toolDirectory = Join-Path $repository ('!tools/NuGet/' + $manifest.version)
$executable = Join-Path $toolDirectory 'nuget.exe'
if (Test-Path -LiteralPath $executable -PathType Leaf) {
    if ((Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash -ne $manifest.exeSha256) {
        throw "Cached NuGet executable SHA-256 mismatch: $executable"
    }
    return $executable
}

# Загружаем во временный файл и публикуем инструмент только после проверки.
[void][IO.Directory]::CreateDirectory($toolDirectory)
$temporaryFile = Join-Path $toolDirectory ([Guid]::NewGuid().ToString('N') + '.download')
try {
    Write-Information "Downloading NuGet $($manifest.version)..." -InformationAction Continue
    Invoke-WebRequest -Uri $manifest.url -OutFile $temporaryFile -UseBasicParsing -TimeoutSec 300
    if ((Get-FileHash -LiteralPath $temporaryFile -Algorithm SHA256).Hash -ne $manifest.exeSha256) {
        throw 'Downloaded NuGet executable SHA-256 mismatch.'
    }
    Move-Item -LiteralPath $temporaryFile -Destination $executable
}
finally {
    if (Test-Path -LiteralPath $temporaryFile) { Remove-Item -LiteralPath $temporaryFile }
}
return $executable