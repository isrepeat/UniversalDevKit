param([string]$LocalPath)

$ErrorActionPreference = 'Stop'
$repositoryPath = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$manifest = Get-Content (Join-Path $repositoryPath 'Scripts/Tools/SolutionInjector.json') -Raw | ConvertFrom-Json

function AssertExecutable([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "SolutionInjector not found: $Path" }
    if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ne $manifest.exeSha256) {
        throw 'SolutionInjector executable SHA-256 mismatch.'
    }
}

# Локальный путь позволяет работать без сети с тем же проверенным бинарником.
if ($LocalPath) {
    $executable = (Resolve-Path -LiteralPath $LocalPath).Path
    AssertExecutable $executable
    return $executable
}

$toolDirectory = Join-Path $repositoryPath ('!tools/SolutionInjector/' + $manifest.version)
$archive = Join-Path $toolDirectory 'distribution.zip'
$executable = Join-Path $toolDirectory 'SolutionInjector.exe'
New-Item -ItemType Directory -Path $toolDirectory -Force | Out-Null
if (Test-Path -LiteralPath $archive) {
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $manifest.archiveSha256) {
        throw "Cached archive SHA-256 mismatch: $archive"
    }
}
else {
    # Сначала проверяем временный архив; неполная загрузка не становится кешем.
    $temporaryArchive = Join-Path $toolDirectory ([Guid]::NewGuid().ToString() + '.zip')
    try {
        Invoke-WebRequest -Uri $manifest.url -OutFile $temporaryArchive -UseBasicParsing
        if ((Get-FileHash -LiteralPath $temporaryArchive -Algorithm SHA256).Hash -ne $manifest.archiveSha256) {
            throw 'Downloaded archive SHA-256 mismatch.'
        }
        Move-Item -LiteralPath $temporaryArchive -Destination $archive
    }
    finally {
        if (Test-Path -LiteralPath $temporaryArchive) { Remove-Item -LiteralPath $temporaryArchive }
    }
}
# Распаковываем проверенный архив повторно, восстанавливая также runtime DLL.
Expand-Archive -LiteralPath $archive -DestinationPath $toolDirectory -Force
AssertExecutable $executable
return $executable