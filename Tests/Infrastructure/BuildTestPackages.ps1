param(
    [ValidateSet('Managed', 'BuildTools', 'Templates', 'AndroidNative', 'WinRt')][string[]]$Family = @('Managed', 'BuildTools', 'Templates'),
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [string]$NuGet = 'nuget.exe',
    [string]$CMake,
    [string]$AndroidNdk,
    [ValidateSet('arm64-v8a', 'armeabi-v7a', 'x86_64')][string]$AndroidAbi = 'arm64-v8a'
)
$env:DOTNET_CLI_UI_LANGUAGE = 'en-US'
$env:VSLANG = '1033'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)

$ErrorActionPreference = 'Stop'
if (-not $CMake -and 'WinRt' -in $Family) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    $CMake = @(& $vswhere -latest -products '*' -find 'Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe')[0]
}
$repository = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$fixtures = Join-Path $repository 'Tests/Fixtures/Packages'
$output = [IO.Path]::GetFullPath($OutputDirectory)
[void][IO.Directory]::CreateDirectory($output)
function InvokeChecked([string]$Tool, [string[]]$Arguments) {
    & $Tool @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "$Tool failed: $LASTEXITCODE" }
}
foreach ($name in $Family) {
    # Каждая сборка использует отдельную копию: исходные fixtures не получают obj/bin.
    $work = Join-Path $output ("w-" + $name + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
    [void][IO.Directory]::CreateDirectory($work)
    Copy-Item -Path (Join-Path $fixtures "$name/*") -Destination $work -Recurse
    Copy-Item -LiteralPath (Join-Path $repository 'LICENSE') -Destination (Join-Path $work 'LICENSE.txt')
    if ($name -eq 'Managed') {
        InvokeChecked 'dotnet' @('pack', (Join-Path $work 'Probe.csproj'), '-c', 'Release', '-o', $output)
    }
    else {
        if ($name -eq 'WinRt') {
            if (-not $CMake) { throw 'WinRt requires CMake.' }
            InvokeChecked $CMake @('-S', $work, '-B', (Join-Path $work 'build'), '-G', 'Visual Studio 18 2026', '-A', 'x64', "-DCMAKE_INSTALL_PREFIX=$work/payload")
            InvokeChecked $CMake @('--build', (Join-Path $work 'build'), '--config', 'Release')
            InvokeChecked $CMake @('--install', (Join-Path $work 'build'), '--config', 'Release')
        }
        if ($name -eq 'AndroidNative') {
            if (-not $CMake -or -not $AndroidNdk) { throw 'AndroidNative requires CMake and AndroidNdk.' }
            $build = Join-Path $work 'build'
            $prefix = Join-Path $work 'payload'
            InvokeChecked $CMake @('-S', $work, '-B', $build, '-G', 'Ninja', "-DCMAKE_TOOLCHAIN_FILE=$AndroidNdk/build/cmake/android.toolchain.cmake", "-DANDROID_ABI=$AndroidAbi", '-DANDROID_PLATFORM=android-24', '-DANDROID_STL=c++_shared', '-DCMAKE_BUILD_TYPE=Release', "-DCMAKE_INSTALL_PREFIX=$prefix")
            InvokeChecked $CMake @('--build', $build)
            InvokeChecked $CMake @('--install', $build)
        }
        InvokeChecked $NuGet @('pack', (Join-Path $work 'Probe.nuspec'), '-BasePath', $work, '-OutputDirectory', $output, '-NonInteractive', '-ForceEnglishOutput')
    }
}
Write-Output "Test packages: $output"