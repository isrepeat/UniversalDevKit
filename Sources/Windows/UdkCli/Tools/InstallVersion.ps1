param(
    [Parameter(Mandatory)][ValidatePattern('\A[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?\z')]
    [string]$Version,
    [Parameter(Mandatory)][string]$Destination
)

$ErrorActionPreference = 'Stop'
$env:DOTNET_CLI_UI_LANGUAGE = 'en-US'
$env:VSLANG = '1033'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)

$tag = "udk-cli-v$Version"
$archiveName = "$tag-windows-x64.zip"
$url = "https://github.com/isrepeat/UniversalDevKit/releases/download/$tag/$archiveName"
$cache = Split-Path -Parent $Destination
$temporary = Join-Path $cache ([Guid]::NewGuid().ToString('N'))
$archive = Join-Path $temporary $archiveName
$payload = Join-Path $temporary 'payload'
$executable = Join-Path $Destination 'udk.exe'

if (Test-Path -LiteralPath $executable -PathType Leaf) { return }
[void][IO.Directory]::CreateDirectory($temporary)
try {
    Write-Host "Downloading UDK CLI $Version..."
    $checksum = "$archive.sha256"
    Invoke-WebRequest -Uri "$url.sha256" -OutFile $checksum -TimeoutSec 60
    $expected = [IO.File]::ReadAllText($checksum).Trim()
    if ($expected -notmatch '\A[0-9a-fA-F]{64}\z') {
        throw "Invalid SHA-256 checksum for UDK CLI $Version."
    }
    Invoke-WebRequest -Uri $url -OutFile $archive -TimeoutSec 300
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $expected) {
        throw "Archive SHA-256 mismatch for UDK CLI $Version."
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::ExtractToDirectory($archive, $payload)
    if (-not (Test-Path -LiteralPath (Join-Path $payload 'udk.exe') -PathType Leaf) -or
        -not (Test-Path -LiteralPath (Join-Path $payload 'Tools') -PathType Container)) {
        throw "The UDK CLI $Version archive must contain udk.exe and Tools."
    }
    try {
        [IO.Directory]::Move($payload, $Destination)
    } catch [IO.IOException] {
        if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) { throw }
    }
} finally {
    [IO.Directory]::Delete($temporary, $true)
}