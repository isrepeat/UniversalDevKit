param([string]$OutputDirectory, [string]$NuGet = 'nuget.exe')
$ErrorActionPreference = 'Stop'
$env:DOTNET_CLI_UI_LANGUAGE = 'en-US'
$env:VSLANG = '1033'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)
$root = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
. (Join-Path $root 'Scripts/PowerShell/ArtifactDirectories.ps1')
$NuGet = & (Join-Path $root 'Scripts/PowerShell/GetNuGet.ps1') -LocalPath $NuGet
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $root '!artifacts/packages/nuget' }
$output = Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) 'AndroidAppPreviewer'
[void][IO.Directory]::CreateDirectory($output)
$lock = [IO.File]::Open((Join-Path $output '.build.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
try {
    $stage = Reset-UdkArtifactDirectory -Root $output -Path (Join-Path $output 'staging')
    $payload = Join-Path $stage 'payload'
    & dotnet publish (Join-Path $root 'Projects/MsBuild/AndroidAppPreviewer/AndroidAppPreviewer.csproj') -c Release -r win-x64 --self-contained true -o (Join-Path $payload 'tools/win-x64') --nologo
    if ($LASTEXITCODE -ne 0) { throw 'Previewer publication failed.' }
    Copy-Item (Join-Path $root 'LICENSE') (Join-Path $payload 'LICENSE.txt')
    Copy-Item (Join-Path $PSScriptRoot 'README.md') (Join-Path $payload 'README.md')
    $version = (Get-Content (Join-Path $root 'Version.json') -Raw | ConvertFrom-Json).version
    $spec = (Get-Content (Join-Path $PSScriptRoot 'Delivery/NuGet/UniversalDevKit.AndroidAppPreviewer.nuspec') -Raw).Replace('{{VERSION}}', $version)
    [IO.File]::WriteAllText((Join-Path $stage 'package.nuspec'), $spec.TrimEnd(), [Text.UTF8Encoding]::new($false))
    & $NuGet pack (Join-Path $stage 'package.nuspec') -BasePath $stage -OutputDirectory $output -NonInteractive -ForceEnglishOutput -Properties 'NoWarn=NU5100'
    if ($LASTEXITCODE -ne 0) { throw 'Previewer packing failed.' }
} finally { $lock.Dispose() }