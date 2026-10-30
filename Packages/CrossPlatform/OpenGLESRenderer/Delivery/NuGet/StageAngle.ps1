param([Parameter(Mandatory)][string]$Payload, [Parameter(Mandatory)][string]$RepositoryPath, [Collections.IDictionary]$Preparations)
$ErrorActionPreference = 'Stop'
$preparedRoot = if ($Preparations -and $Preparations.Contains('Dynamic')) { $Preparations['Dynamic']['UniversalDevKitAngleRoot'] } else { $env:UDK_ANGLE_ROOT }
if (-not $preparedRoot) { throw 'Prepare ANGLE first or set UDK_ANGLE_ROOT to its installation.' }
$angleRoot = (Resolve-Path -LiteralPath $preparedRoot).Path
foreach ($configuration in @('Debug', 'Release')) {
    $source = Join-Path $angleRoot "runtimes/win-x64/native/$configuration"
    if (-not (Test-Path -LiteralPath $source)) {
        $source = Join-Path $angleRoot 'bin'
        if ($configuration -eq 'Debug' -and (Test-Path (Join-Path $angleRoot 'debug/bin'))) { $source = Join-Path $angleRoot 'debug/bin' }
    }
    $libraryRoot = $source
    if (-not (Test-Path (Join-Path $libraryRoot 'libEGL.lib'))) {
        $libraryRoot = Join-Path $angleRoot 'lib'
        if ($configuration -eq 'Debug' -and (Test-Path (Join-Path $angleRoot 'debug/lib'))) { $libraryRoot = Join-Path $angleRoot 'debug/lib' }
    }
    $destination = Join-Path $Payload "assets/ANGLE/$configuration"
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    foreach ($name in @('libEGL', 'libGLESv2')) {
        Copy-Item -LiteralPath (Join-Path $source "$name.dll") -Destination $destination
        Copy-Item -LiteralPath (Join-Path $libraryRoot "$name.lib") -Destination $destination
    }
    foreach ($name in @('z.dll', 'zd.dll')) {
        if (Test-Path (Join-Path $source $name)) { Copy-Item -LiteralPath (Join-Path $source $name) -Destination $destination }
    }
}
$license = Join-Path $angleRoot 'licenses/ANGLE.copyright'
if (-not (Test-Path $license)) { $license = Join-Path $angleRoot 'share/angle/copyright' }
$licenses = Join-Path $Payload 'licenses'
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Angle.targets') -Destination (Join-Path $Payload 'build/native/Angle.targets')
New-Item -ItemType Directory -Path $licenses -Force | Out-Null
Copy-Item -LiteralPath $license -Destination (Join-Path $licenses 'ANGLE.copyright')
foreach ($name in @('stb_truetype.h', 'nanosvg.h', 'nanosvgrast.h')) {
    Copy-Item -LiteralPath (Join-Path $RepositoryPath "ThirdParty/XamlRuntime/$name") -Destination $licenses
}