param([string]$OutputDirectory, [string]$CMake, [string]$NuGet = 'nuget.exe', [string]$AngleRoot)
$ErrorActionPreference = 'Stop'
$env:DOTNET_CLI_UI_LANGUAGE = 'en-US'
$env:VSLANG = '1033'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)
$root = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
. (Join-Path $root 'Scripts/PowerShell/ArtifactDirectories.ps1')
$NuGet = & (Join-Path $root 'Scripts/PowerShell/GetNuGet.ps1') -LocalPath $NuGet
if (-not $CMake) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    $CMake = @(& $vswhere -latest -products '*' -find 'Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe')[0]
}
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $root '!artifacts/packages/nuget' }
$output = Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) 'AndroidAppPreviewerPluginSdk'
[void][IO.Directory]::CreateDirectory($output)
$lock = [IO.File]::Open((Join-Path $output '.build.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
try {
    $stage = Reset-UdkArtifactDirectory -Root $output -Path (Join-Path $output 'staging')
    $payload = Join-Path $stage 'payload'
    $native = Join-Path $payload 'native'
    $build = Join-Path $root '!artifacts/projects/windows/cmake/AndroidAppPreviewerPluginSdk'
    $prepare = Join-Path $root 'Packages/CrossPlatform/OpenGLESRenderer/Delivery/NuGet/PrepareAngle.ps1'
    $prepared = if ($AngleRoot) {
        @{ UniversalDevKitAngleRoot = (Resolve-Path -LiteralPath $AngleRoot).Path }
    } else {
        & $prepare -RepositoryPath $root -WorkDirectory (Join-Path $output 'dependencies/ANGLE') -Runtime Dynamic -Configurations Debug,Release -Generator 'Visual Studio 18 2026'
    }
    & $CMake -S $root -B $build -G 'Visual Studio 18 2026' -A x64 '-DUniversalDevKit_COMPONENTS=OpenGLESRenderer' '-DUniversalDevKit_BUILD_STATIC=ON' '-DUniversalDevKit_BUILD_DYNAMIC=OFF' '-DUniversalDevKit_INSTALL=ON' "-DUniversalDevKitAngleRoot=$($prepared.UniversalDevKitAngleRoot)" "-DCMAKE_INSTALL_PREFIX=$native"
    if ($LASTEXITCODE -ne 0) { throw 'Preview SDK native configuration failed.' }
    foreach ($configuration in @('Debug', 'Release')) {
        & $CMake --build $build --config $configuration --parallel 2
        if ($LASTEXITCODE -ne 0) { throw "Preview SDK native $configuration build failed." }
        & $CMake --install $build --config $configuration
        if ($LASTEXITCODE -ne 0) { throw "Preview SDK native $configuration installation failed." }
    }
    [void][IO.Directory]::CreateDirectory((Join-Path $payload 'cmake'))
    Copy-Item (Join-Path $root 'Includes/Windows/AndroidAppPreviewerPluginSdk') (Join-Path $payload 'include') -Recurse
    [void][IO.Directory]::CreateDirectory((Join-Path $payload 'src'))
    foreach ($directory in @('Internal', 'Session')) {
        Copy-Item (Join-Path $root "Sources/Windows/AndroidAppPreviewerPluginSdk/$directory") (Join-Path $payload 'src') -Recurse
    }
    Copy-Item (Join-Path $root 'Projects/Cmake/AndroidAppPreviewerPluginSdk/AndroidAppPreviewerPluginConfig.cmake') (Join-Path $payload 'cmake')
    & dotnet build (Join-Path $root 'Projects/MsBuild/AndroidAppPreviewerPluginSdk/AndroidAppPreviewerPluginSdk.csproj') -c Release --nologo
    if ($LASTEXITCODE -ne 0) { throw 'Preview SDK managed build failed.' }
    [void][IO.Directory]::CreateDirectory((Join-Path $payload 'lib/net8.0'))
    Copy-Item (Join-Path $root '!artifacts/projects/windows/msbuild/AndroidAppPreviewerPluginSdk/bin/Release/net8.0/AndroidAppPreviewer.PluginSDK.dll') (Join-Path $payload 'lib/net8.0')
    Copy-Item (Join-Path $root 'LICENSE') (Join-Path $payload 'LICENSE.txt')
    Copy-Item (Join-Path $PSScriptRoot 'README.md') (Join-Path $payload 'README.md')
    [void][IO.Directory]::CreateDirectory((Join-Path $payload 'licenses'))
    Copy-Item (Join-Path $prepared.UniversalDevKitAngleRoot 'share/angle/copyright') (Join-Path $payload 'licenses/ANGLE.copyright')
    foreach ($name in @('stb_truetype.h', 'nanosvg.h', 'nanosvgrast.h')) {
        Copy-Item (Join-Path $root "ThirdParty/XamlRuntime/$name") (Join-Path $payload 'licenses')
    }
    $version = (Get-Content (Join-Path $root 'Version.json') -Raw | ConvertFrom-Json).version
    $spec = (Get-Content (Join-Path $PSScriptRoot 'Delivery/NuGet/UniversalDevKit.AndroidAppPreviewer.PluginSDK.nuspec') -Raw).Replace('{{VERSION}}', $version)
    [IO.File]::WriteAllText((Join-Path $stage 'package.nuspec'), $spec.TrimEnd(), [Text.UTF8Encoding]::new($false))
    & $NuGet pack (Join-Path $stage 'package.nuspec') -BasePath $stage -OutputDirectory $output -NonInteractive -ForceEnglishOutput -Properties 'NoWarn=NU5100;NU5128'
    if ($LASTEXITCODE -ne 0) { throw 'Preview SDK packing failed.' }
} finally { $lock.Dispose() }