param(
    [Parameter(Mandatory)][string]$RepositoryPath,
    [Parameter(Mandatory)][string]$WorkDirectory,
    [Parameter(Mandatory)][ValidateSet('Dynamic')][string]$Runtime,
    [Parameter(Mandatory)][ValidateSet('Debug', 'Release')][string[]]$Configurations,
    [Parameter(Mandatory)][string]$Generator
)

$ErrorActionPreference = 'Stop'
$encoding = [Text.UTF8Encoding]::new($false)
[Console]::InputEncoding = $encoding
[Console]::OutputEncoding = $encoding
$OutputEncoding = $encoding

# Используем установленный vcpkg; его binary cache учитывает ABI, рецепт и патчи.
$candidates = @()
if ($env:VCPKG_ROOT) { $candidates += Join-Path $env:VCPKG_ROOT 'vcpkg.exe' }
$command = Get-Command vcpkg.exe -ErrorAction SilentlyContinue
if ($command) { $candidates += $command.Source }
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
if (Test-Path -LiteralPath $vswhere) {
    $candidates += @(& $vswhere -latest -products '*' -find 'VC/vcpkg/vcpkg.exe')
}
$vcpkg = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if (-not $vcpkg) { throw 'vcpkg.exe was not found. Set VCPKG_ROOT or install the Visual Studio vcpkg component.' }

$repository = (Resolve-Path -LiteralPath $RepositoryPath).Path
$recipe = Join-Path $repository 'ThirdParty/XamlRuntime/ANGLE'
$manifest = Join-Path $recipe 'vcpkg.json'
$overlay = Join-Path $recipe 'CustomRecipes'
if (-not (Test-Path -LiteralPath $manifest -PathType Leaf) -or
    -not (Test-Path -LiteralPath (Join-Path $overlay 'angle/portfile.cmake') -PathType Leaf)) {
    throw 'The pinned ANGLE manifest and overlay recipe are required.'
}
[void][IO.Directory]::CreateDirectory($WorkDirectory)
$work = (Resolve-Path -LiteralPath $WorkDirectory).Path
$downloadCache = Join-Path $repository '!artifacts/cache/vcpkg/downloads'
$binaryCache = Join-Path $repository '!artifacts/cache/vcpkg/binaries'
[void][IO.Directory]::CreateDirectory($downloadCache)
[void][IO.Directory]::CreateDirectory($binaryCache)

# Короткий путь нужен Ninja и инструментам ANGLE из-за глубокого дерева исходников.
$drive = $null
foreach ($letter in @('Z', 'Y', 'X', 'W', 'V', 'U', 'T')) {
    $candidate = "$letter`:"
    if (Test-Path -LiteralPath "$candidate\") { continue }
    & subst $candidate $work | Out-Host
    if ($LASTEXITCODE -eq 0) { $drive = $candidate; break }
}
if (-not $drive) { throw 'No free drive letter is available for the temporary ANGLE build path.' }

try {
    # Рабочая копия сохраняет формат patch, не меняя исходный рецепт в репозитории.
    $workingOverlay = Join-Path "$drive\" 'CustomRecipes'
    [void][IO.Directory]::CreateDirectory($workingOverlay)
    foreach ($file in Get-ChildItem -LiteralPath $overlay -Recurse -File) {
        $relative = $file.FullName.Substring($overlay.Length + 1)
        $destination = Join-Path $workingOverlay $relative
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
        if ($file.Extension -eq '.patch') {
            $content = [IO.File]::ReadAllText($file.FullName).TrimEnd([char]13, [char]10) + "`n"
            [IO.File]::WriteAllText($destination, $content, $encoding)
        } else {
            Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
        }
    }
    $arguments = @(
        'install',
        "--x-manifest-root=$recipe",
        "--overlay-ports=$workingOverlay",
        "--x-install-root=$drive\installed",
        "--x-buildtrees-root=$drive\buildtrees",
        "--x-packages-root=$drive\packages",
        "--downloads-root=$downloadCache",
        '--triplet=x64-windows',
        '--host-triplet=x64-windows',
        '--binarycaching'
    )
    # Пользовательские источники кеша имеют приоритет; по умолчанию включён локальный кеш UDK.
    if (-not $env:VCPKG_BINARY_SOURCES) { $arguments += "--binarysource=clear;files,$binaryCache,readwrite" }
    Write-Host "Preparing ANGLE for Windows x64, CRT $Runtime, configurations $($Configurations -join ', ')..."
    & $vcpkg @arguments | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "ANGLE dependency preparation failed (vcpkg exit code $LASTEXITCODE)." }
} finally {
    & subst $drive /d | Out-Host
    if ($LASTEXITCODE -ne 0) { Write-Warning "Could not release temporary drive $drive" }
}

# Наружу возвращаем настоящий путь, который продолжит работать после удаления subst.
$installed = Join-Path $work 'installed/x64-windows'
$required = @('include/GLES3/gl3.h', 'include/EGL/egl.h', 'share/angle/copyright')
foreach ($configuration in $Configurations) {
    $prefix = if ($configuration -eq 'Debug') { 'debug/' } else { '' }
    $required += @("${prefix}lib/libEGL.lib", "${prefix}lib/libGLESv2.lib", "${prefix}bin/libEGL.dll", "${prefix}bin/libGLESv2.dll")
    $required += if ($configuration -eq 'Debug') { 'debug/bin/zd.dll' } else { 'bin/z.dll' }
}
foreach ($relative in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $installed $relative) -PathType Leaf)) {
        throw "Prepared ANGLE artifact is missing: $relative"
    }
}
@{ UniversalDevKitAngleRoot = $installed }