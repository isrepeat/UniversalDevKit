param(
    [Parameter(Mandatory)][ValidateSet('AndroidBuildTools', 'AndroidTemplates')][string]$Package,
    [string]$OutputDirectory,
    [string]$NuGet
)
$ErrorActionPreference = 'Stop'
$env:DOTNET_CLI_UI_LANGUAGE = 'en-US'
$env:VSLANG = '1033'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)
$repository = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
. (Join-Path $repository 'Scripts/PowerShell/ArtifactDirectories.ps1')
$NuGet = & (Join-Path $repository 'Scripts/PowerShell/GetNuGet.ps1') -LocalPath $NuGet
$packageRoot = Join-Path $repository "Packages/Android/$Package"
$definition = Get-Content (Join-Path $packageRoot 'Package.json') -Raw | ConvertFrom-Json
$deliveryFile = Join-Path $packageRoot $definition.deliveries.NuGet
$delivery = Get-Content $deliveryFile -Raw | ConvertFrom-Json
if ($definition.schemaVersion -ne 1 -or $delivery.schemaVersion -ne 1 -or $delivery.adapter -ne 'content') {
    throw 'Unsupported content package definition.'
}
$version = (Get-Content (Join-Path $packageRoot $definition.versionSource) -Raw | ConvertFrom-Json).version
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repository '!artifacts/packages/nuget' }
$output = Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) $Package
[void][IO.Directory]::CreateDirectory($output)
$buildLock = $null
$drive = $null
try {
    $buildLock = [IO.File]::Open((Join-Path $output '.build.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    $drive = New-UdkArtifactDrive -Path $output
    $stage = Reset-UdkArtifactDirectory -Root $drive.Path -Path (Join-Path $drive.Path "staging/$Package")
    $payload = Join-Path $stage 'payload'
    [void][IO.Directory]::CreateDirectory($payload)
    # Состав поставки задаётся delivery; реализация находится в Sources, публичные заголовки — в Includes, проекты — в Projects.
    if ($delivery.files -isnot [Array] -or -not $delivery.files.Count) { throw 'Content delivery requires a nonempty files array.' }
    foreach ($mapping in $delivery.files) {
        foreach ($field in @('source', 'target')) {
            if ($mapping.$field -isnot [string] -or [string]::IsNullOrWhiteSpace($mapping.$field) -or
                $mapping.$field -match '[\\:*?;$@%\r\n]' -or
                @($mapping.$field.Split('/') | Where-Object { $_ -in @('', '.', '..') }).Count) {
                throw "Invalid content mapping $field."
            }
        }
        $source = Join-Path $repository $mapping.source
        $destination = Join-Path $payload $mapping.target
        if (Test-Path -LiteralPath $source -PathType Container) {
            [void][IO.Directory]::CreateDirectory($destination)
            Get-ChildItem -LiteralPath $source -Force | ForEach-Object {
                Copy-Item -LiteralPath $_.FullName -Destination $destination -Recurse -Force
            }
        } elseif (Test-Path -LiteralPath $source -PathType Leaf) {
            [void][IO.Directory]::CreateDirectory((Split-Path $destination))
            Copy-Item -LiteralPath $source -Destination $destination -Force
        } else { throw "Content source does not exist: $source" }
    }
    Copy-Item (Join-Path $packageRoot 'README.md') $payload
    Copy-Item (Join-Path $repository 'LICENSE') (Join-Path $payload 'LICENSE.txt')
    $spec = (Get-Content (Join-Path (Split-Path $deliveryFile) $delivery.nuspec) -Raw).Replace('{{VERSION}}', $version)
    $specPath = Join-Path $stage "$Package.nuspec"
    [IO.File]::WriteAllText($specPath, $spec.TrimEnd([char]13, [char]10), [Text.UTF8Encoding]::new($false))
    & $NuGet pack $specPath -BasePath $payload -OutputDirectory $drive.Path -NonInteractive -ForceEnglishOutput -NoDefaultExcludes -Properties 'NoWarn=NU5100;NU5111;NU5128'
    if ($LASTEXITCODE -ne 0) { throw "Packing $Package failed." }
    Write-Host "Package: $(Join-Path $output "$($delivery.id).$version.nupkg")"
} finally {
    if ($drive) { Remove-UdkArtifactDrive $drive }
    if ($buildLock) { $buildLock.Dispose() }
}