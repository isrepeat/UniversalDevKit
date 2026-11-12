param(
    [ValidateLength(1, 80)]
    [ValidatePattern('\A[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?\z')]
    [string]$Version
)

$ErrorActionPreference = 'Stop'
$env:DOTNET_CLI_UI_LANGUAGE = 'en-US'
$env:VSLANG = '1033'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
. (Join-Path $root 'Sources\Windows\UdkCli\Tools\ResolveJsonReference.ps1')
$componentPath = Join-Path $root 'Projects\Components\Application\UdkCli.json'
$component = Get-Content -LiteralPath $componentPath -Raw -Encoding UTF8 | ConvertFrom-Json
Resolve-UdkDescriptionVersion $root $component $componentPath 'githubVersion'
if (-not $Version) { $Version = $component.githubVersion }
if ($Version -isnot [string] -or $Version.Length -gt 80 -or $Version -notmatch '\A[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?\z') {
    throw 'A valid release version is required.'
}
$repository = 'isrepeat/UniversalDevKit'
$tag = "udk-cli-v$Version"
$commit = & git -C $root rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'Could not resolve the release commit.' }

$msbuild = (Get-Command MSBuild.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $msbuild) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path -LiteralPath $vswhere -PathType Leaf) {
        $msbuild = & $vswhere -latest -products '*' -requires Microsoft.Component.MSBuild Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -find 'MSBuild\Current\Bin\MSBuild.exe' | Select-Object -First 1
    }
}
if (-not $msbuild) { throw 'MSBuild with the Visual C++ toolset was not found.' }

$dotnet = (Get-Command dotnet.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source

$releaseDirectory = Join-Path $root "!artifacts\releases\UdkCli\$tag\$([Guid]::NewGuid().ToString('N'))"
$cacheDirectory = Join-Path $root '!artifacts\projects\Windows-x64\UdkCli.Release'
$buildDirectory = Join-Path $cacheDirectory 'cpp\bin'
$objectDirectory = Join-Path $cacheDirectory 'cpp\obj'
$setupOutput = Join-Path $cacheDirectory 'wpf\publish'
$cachedPayload = Join-Path $cacheDirectory 'UdkPayload.zip'
$vsixOutput = Join-Path $cacheDirectory 'vsix\bin'
$vsixProject = Join-Path $root 'Projects\MsBuild\Application\UdkCli.VisualStudio\UdkCli.VisualStudio.csproj'
$vsix = Join-Path $vsixOutput 'UdkCli.VisualStudio.vsix'
$toolsDirectory = Join-Path $root 'Sources\Windows\UdkCli\Tools'
$packageDirectory = Join-Path $releaseDirectory 'package'
$archive = Join-Path $releaseDirectory "$tag-windows-x64.zip"
$installerName = "$tag-setup-windows-x64"
$installer = Join-Path $releaseDirectory "$installerName.exe"
$project = Join-Path $root 'Projects\MsBuild\Application\UdkCli\UdkCli.vcxproj'

[void][IO.Directory]::CreateDirectory($cacheDirectory)
$buildLock = [IO.File]::Open((Join-Path $cacheDirectory 'build.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
try {
    & $msbuild $project /nologo /m /t:Build /p:Configuration=Release /p:Platform=x64 "/p:UniversalDevKitGitHubVersion=$Version" "/p:OutDir=$buildDirectory\" "/p:IntDir=$objectDirectory\"
    if ($LASTEXITCODE -ne 0) { throw 'UdkCli build failed.' }

    $cli = Join-Path $buildDirectory 'udk.exe'
    if (-not (Test-Path -LiteralPath $cli -PathType Leaf)) { throw 'Build output is missing udk.exe.' }
    [void][IO.Directory]::CreateDirectory($packageDirectory)
    Copy-Item -LiteralPath $cli, (Join-Path $root 'LICENSE') -Destination $packageDirectory
    Copy-Item -LiteralPath $toolsDirectory -Destination $packageDirectory -Recurse
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory($packageDirectory, $archive)

    # Keep the resource timestamp stable so MSBuild can reuse the WPF assembly and bundle.
    if (-not (Test-Path -LiteralPath $cachedPayload -PathType Leaf) -or
        (Get-FileHash -LiteralPath $cachedPayload).Hash -ne (Get-FileHash -LiteralPath $archive).Hash) {
        Copy-Item -LiteralPath $archive -Destination $cachedPayload -Force
    }

    & $msbuild $vsixProject /nologo /m /restore /p:Configuration=Release "/p:OutDir=$vsixOutput\" "/p:ArtifactsPath=$cacheDirectory\vsix"
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $vsix -PathType Leaf)) { throw 'UDK Visual Studio extension build failed.' }

    $setupProject = Join-Path $root 'Projects\MsBuild\Application\UdkCli.Setup\UdkCli.Setup.csproj'
    $dotnetArguments = @(
        'publish', $setupProject, '-c', 'Release', '-r', 'win-x64', '--self-contained', 'true',
        '--artifacts-path', (Join-Path $cacheDirectory 'wpf'), '-o', $setupOutput,
        '-p:PublishSingleFile=true', '-p:IncludeNativeLibrariesForSelfExtract=true',
        '-p:EnableCompressionInSingleFile=true', '-p:DebugType=None', '-p:IncludeSourceRevisionInInformationalVersion=false',
        "-p:Version=$Version", "-p:UdkPayload=$cachedPayload", "-p:UdkVsixPayload=$vsix"
    )
    & $dotnet @dotnetArguments
    if ($LASTEXITCODE -ne 0) { throw 'UdkCli installer compilation failed.' }
    Copy-Item -LiteralPath (Join-Path $setupOutput 'UdkCli.Setup.exe') -Destination $installer
} finally {
    $buildLock.Dispose()
}

$archiveHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
$archiveChecksum = "$archive.sha256"
[IO.File]::WriteAllText($archiveChecksum, $archiveHash)
Write-Host "Archive: $archive"
Write-Host "SHA-256: $archiveHash"
Write-Host "Checksum file: $archiveChecksum"
Write-Host "Installer: $installer"
Write-Host "SHA-256: $((Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash)"
Write-Host "GitHub release: $repository $tag"
Write-Host "Target commit: $commit"
if ((Read-Host 'Publish this release? [y/N]') -notin @('y', 'yes')) {
    Write-Host 'Publication cancelled. The local files are available at the paths above.'
    return
}

$gh = (Get-Command gh.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$releaseArguments = @('release', 'create', $tag, $archive, $archiveChecksum, $installer, '--repo', $repository, '--target', $commit,
    '--title', "UDK CLI $Version", '--notes', "Windows x64 build from commit $commit.", '--latest=false')
if ($Version.Contains('-')) { $releaseArguments += '--prerelease' }
& $gh @releaseArguments
if ($LASTEXITCODE -ne 0) { throw "GitHub publication failed. The local files are available in $releaseDirectory." }