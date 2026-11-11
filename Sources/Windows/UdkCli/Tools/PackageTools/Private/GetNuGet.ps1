param([string]$LocalPath, [Parameter(Mandatory)][string]$CacheDirectory)

$ErrorActionPreference = 'Stop'
$env:DOTNET_CLI_UI_LANGUAGE = 'en-US'
$env:VSLANG = '1033'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)

function Get-UdkToolHash([string]$Path) {
    $algorithm = [Security.Cryptography.SHA256]::Create()
    $stream = [IO.File]::OpenRead($Path)
    try {
        return [BitConverter]::ToString($algorithm.ComputeHash($stream)).Replace('-', '')
    }
    finally {
        $stream.Dispose()
        $algorithm.Dispose()
    }
}


if ($LocalPath -and $LocalPath -ne 'nuget.exe') {
    return (Get-Command $LocalPath -CommandType Application -ErrorAction Stop).Source
}

$manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'NuGet.json') -Raw | ConvertFrom-Json
$toolDirectory = Join-Path $CacheDirectory ('NuGet/' + $manifest.version)
$executable = Join-Path $toolDirectory 'nuget.exe'
if (Test-Path -LiteralPath $executable -PathType Leaf) {
    if ((Get-UdkToolHash $executable) -ne $manifest.exeSha256) {
        throw "Cached NuGet executable SHA-256 mismatch: $executable"
    }
    return $executable
}

# Download to a temporary file. Use the tool only after checking it.
[void][IO.Directory]::CreateDirectory($toolDirectory)
$temporaryFile = Join-Path $toolDirectory ([Guid]::NewGuid().ToString('N') + '.download')
try {
    Write-Information "Downloading NuGet $($manifest.version)..." -InformationAction Continue
    Invoke-WebRequest -Uri $manifest.url -OutFile $temporaryFile -UseBasicParsing -TimeoutSec 300
    if ((Get-UdkToolHash $temporaryFile) -ne $manifest.exeSha256) {
        throw 'Downloaded NuGet executable SHA-256 mismatch.'
    }
    Move-Item -LiteralPath $temporaryFile -Destination $executable
}
finally {
    if (Test-Path -LiteralPath $temporaryFile) {
        Remove-Item -LiteralPath $temporaryFile
    }
}
return $executable