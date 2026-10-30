param([string]$OutputDirectory, [string]$CMake, [string]$NuGet = 'nuget.exe')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../../../Scripts/PowerShell/ArtifactDirectories.ps1')
$env:DOTNET_CLI_UI_LANGUAGE = 'en-US'
$env:VSLANG = '1033'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)
$root = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$NuGet = & (Join-Path $root 'Scripts/PowerShell/GetNuGet.ps1') -LocalPath $NuGet
if (-not $CMake) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    $CMake = @(& $vswhere -latest -products '*' -find 'Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe')[0]
}
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $root '!artifacts/packages/nuget' }
$output = Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) 'XamlCompiler'
$version = (Get-Content (Join-Path $root 'Version.json') -Raw | ConvertFrom-Json).version
[void][IO.Directory]::CreateDirectory($output)
$buildLock = $null
$artifactDrive = $null
$transcriptStarted = $false
try {
try {
    $buildLock = [IO.File]::Open((Join-Path $output '.build.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
} catch { throw "Another build owns the component directory: $output" }
Start-Transcript -Path (Join-Path $output 'build.log') -Force | Out-Null
$transcriptStarted = $true
$artifactDrive = New-UdkArtifactDrive -Path $output
$physicalOutput = $output
$output = $artifactDrive.Path
$archive = Join-Path $physicalOutput "UniversalDevKit.XamlCompiler.$version.nupkg"
$build = Join-Path $output 'build'
& $CMake -S (Join-Path $root 'Projects/Cmake/XamlCompiler') -B $build -G 'Visual Studio 18 2026' -A x64
if ($LASTEXITCODE -ne 0) { throw 'Host compiler configuration failed.' }
& $CMake --build $build --config Release
if ($LASTEXITCODE -ne 0) { throw 'Host compiler build failed.' }
$stage = Reset-UdkArtifactDirectory -Root $output -Path (Join-Path $output 'staging/XamlCompiler')
$tools = Join-Path $stage 'payload/tools/win-x64'
New-Item -ItemType Directory -Path $tools -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $build 'Release/XamlCompiler.exe') -Destination $tools
Copy-Item -LiteralPath (Join-Path $root 'LICENSE') -Destination (Join-Path $stage 'payload/LICENSE.txt')
$spec = (Get-Content (Join-Path $PSScriptRoot 'Delivery/NuGet/UniversalDevKit.XamlCompiler.nuspec') -Raw).Replace('{{VERSION}}', $version)
[IO.File]::WriteAllText((Join-Path $stage 'XamlCompiler.nuspec'), $spec.TrimEnd(), [Text.UTF8Encoding]::new($false))
& $NuGet pack (Join-Path $stage 'XamlCompiler.nuspec') -BasePath $stage -OutputDirectory $output -NonInteractive -ForceEnglishOutput -Properties 'NoWarn=NU5100'
if ($LASTEXITCODE -ne 0) { throw 'Host compiler packing failed.' }
Write-Host "Host compiler package: $archive"
} finally {
    if ($artifactDrive) { Remove-UdkArtifactDrive $artifactDrive }
    if ($transcriptStarted) { Stop-Transcript | Out-Null }
    if ($buildLock) { $buildLock.Dispose() }
}