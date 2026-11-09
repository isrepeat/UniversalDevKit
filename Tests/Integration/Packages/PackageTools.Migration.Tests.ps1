param([string]$BaselineDirectory, [switch]$CheckMaven)
$ErrorActionPreference = 'Stop'
$env:DOTNET_CLI_UI_LANGUAGE = 'en-US'
$env:VSLANG = '1033'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)
$root = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$builder = Join-Path $root 'Packages/Build/Build.ps1'
$definitions = @(Get-ChildItem (Join-Path $root 'Packages') -Filter Package.json -Recurse -File)
$plans = @(& $builder -All -Plan)
if ($definitions.Count -ne 10 -or $plans.Count -ne 14) { throw 'Unexpected package or delivery matrix.' }
foreach ($file in $definitions) {
    if ((Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json).schemaVersion -ne 2) { throw "Unmigrated package: $file" }
}
foreach ($old in @('Packages/Build/NuGet/Build.ps1','Packages/Build/Content/Build.ps1','Packages/Build/Android/Build.ps1','Packages/Build/Android/BuildKotlin.ps1','Packages/Windows/XamlCompiler/Build.ps1')) {
    if (Test-Path -LiteralPath (Join-Path $root $old)) { throw "Legacy packer remains: $old" }
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Get-PackageContract([string]$Path) {
    $archive = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $names = @($archive.Entries | ForEach-Object { $_.FullName.Replace('\','/') } | Where-Object { $_ -notmatch '^(_rels/|package/)' -and $_ -ne '[Content_Types].xml' -and -not $_.EndsWith('/') } | Sort-Object)
        $spec = @($archive.Entries | Where-Object { $_.FullName -like '*.nuspec' })[0]
        $reader = [IO.StreamReader]::new($spec.Open())
        try { [xml]$xml = $reader.ReadToEnd() } finally { $reader.Dispose() }
        $dependencies = @($xml.SelectNodes('//*[local-name()="dependency"]') | ForEach-Object { $_.GetAttribute('id') + '=' + $_.GetAttribute('version') } | Sort-Object)
        return [pscustomobject]@{ Names=$names; Dependencies=$dependencies; Id=$xml.package.metadata.id; Version=$xml.package.metadata.version }
    } finally { $archive.Dispose() }
}
foreach ($plan in ($plans | Where-Object DeliveryName -eq 'NuGet')) {
    $package = Join-Path $root ('!artifacts/packages/nuget/' + $plan.Package.name + '/' + $plan.Delivery.id + '.' + $plan.Version + '.nupkg')
    if (-not (Test-Path -LiteralPath $package)) { throw "Package was not emitted: $package" }
    $actual = Get-PackageContract $package
    if ($actual.Id -cne $plan.Delivery.id -or $actual.Version -cne $plan.Version) { throw 'Package identity changed.' }
    if ($BaselineDirectory) {
        $baseline = Join-Path $BaselineDirectory (Split-Path -Leaf $package)
        if (Test-Path -LiteralPath $baseline) {
            $expected = Get-PackageContract $baseline
            if (($actual.Names -join "`n") -cne ($expected.Names -join "`n")) {
                Compare-Object $expected.Names $actual.Names | Out-Host
                throw "Package file composition changed: $package"
            }
            if (($actual.Dependencies -join ';') -cne ($expected.Dependencies -join ';')) { throw "Package dependencies changed: $package" }
            Write-Host "Composition and dependencies preserved: $($actual.Id)"
        }
    }
}
if ($CheckMaven) {
    foreach ($plan in ($plans | Where-Object DeliveryName -eq 'Android')) {
        if ($plan.Delivery.adapter -eq 'maven-repository') {
            $artifact = $plan.Delivery.artifactId
            $variants = @($artifact)
        } else {
            $project = @($plan.Projects.Values | Where-Object adapter -eq 'udk-prefab')[0]
            $registry = Get-Content (Join-Path $root "Projects/Components/$($project.component).json") -Raw | ConvertFrom-Json
            $modes = if ($registry.kind -eq 'headerOnly') { @('shared') } elseif ($registry.stateScope -eq 'process') { @('dynamic') } else { @('static','dynamic') }
            $variants = @($modes | ForEach-Object { $plan.Delivery.artifactPrefix + '-' + $_ + '-release' })
        }
        foreach ($artifact in $variants) {
            $coordinate = Join-Path $root ('!artifacts/packages/maven/' + $plan.Delivery.groupId.Replace('.','/') + '/' + $artifact + '/' + $plan.Version + '/' + $artifact + '-' + $plan.Version)
            foreach ($extension in @('aar','pom')) { if (-not (Test-Path -LiteralPath ($coordinate + '.' + $extension))) { throw "Missing Maven publication: $coordinate.$extension" } }
            if ($plan.Delivery.adapter -eq 'maven-prefab') {
                $archive = [IO.Compression.ZipFile]::OpenRead($coordinate + '.aar')
                try {
                    $entries = @($archive.Entries.FullName)
                    foreach ($required in @('AndroidManifest.xml','LICENSE.txt','prefab/prefab.json','udk-release.json')) { if ($required -cnotin $entries) { throw "Incomplete Prefab archive: $required" } }
                    if (@($entries | Where-Object { $_.Contains('\') }).Count) { throw 'Nonportable ZIP paths in AAR.' }
                    if ($registry.kind -ne 'headerOnly') {
                        foreach ($abi in @('arm64-v8a','x86_64')) { if (-not @($entries | Where-Object { $_ -like "*/libs/android.$abi/*" }).Count) { throw "Missing Prefab ABI: $abi" } }
                    }
                } finally { $archive.Dispose() }
            }
        }
    }
}
Write-Host 'PASS: one schema, one release engine, preserved identities and package contracts.'