param(
    [ValidatePattern('^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$')]
    [string]$Version
)

$ErrorActionPreference = 'Stop'
$env:DOTNET_CLI_UI_LANGUAGE = 'en-US'
$env:VSLANG = '1033'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)

$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
. (Join-Path $root 'Sources/Windows/UdkCli/Tools/ResolveJsonReference.ps1')
$componentPath = Join-Path $root 'Projects/Components/UdkCli.json'
$component = Get-Content -LiteralPath $componentPath -Raw | ConvertFrom-Json
Resolve-UdkDescriptionVersion $root $component $componentPath 'githubVersion'
if (-not $Version) { $Version = $component.githubVersion }
if ($Version -isnot [string] -or $Version -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$') {
    throw 'A valid release version is required.'
}
$repository = 'isrepeat/UniversalDevKit'
$tag = "udk-cli-v$Version"
$commit = & git -C $root rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'Could not resolve the release commit.' }

$msbuild = (Get-Command MSBuild.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $msbuild) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    if (Test-Path -LiteralPath $vswhere -PathType Leaf) {
        $msbuild = & $vswhere -latest -products '*' -requires Microsoft.Component.MSBuild Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -find 'MSBuild\Current\Bin\MSBuild.exe' | Select-Object -First 1
    }
}
if (-not $msbuild) { throw 'MSBuild with the Visual C++ toolset was not found.' }

$releaseDirectory = Join-Path $root "!artifacts/releases/UdkCli/$tag/$([Guid]::NewGuid().ToString('N'))"
$buildDirectory = Join-Path $releaseDirectory 'build'
$packageDirectory = Join-Path $releaseDirectory 'package'
$archive = Join-Path $releaseDirectory "$tag-windows-x64.zip"
$project = Join-Path $root 'Projects/MsBuild/UdkCli/UdkCli.vcxproj'

& $msbuild $project /nologo /m /t:Build /p:Configuration=Release /p:Platform=x64 "/p:OutDir=$buildDirectory/" "/p:IntDir=$releaseDirectory/obj/"
if ($LASTEXITCODE -ne 0) { throw 'UdkCli build failed.' }

foreach ($file in @('udk.exe', 'Tools/ProjectTools/Generate.ps1', 'Tools/PackageTools/Build.ps1')) {
    if (-not (Test-Path -LiteralPath (Join-Path $buildDirectory $file) -PathType Leaf)) {
        throw "Build output is missing $file."
    }
}
[void][IO.Directory]::CreateDirectory($packageDirectory)
Copy-Item -LiteralPath (Join-Path $buildDirectory 'udk.exe'), (Join-Path $root 'LICENSE') -Destination $packageDirectory
Copy-Item -LiteralPath (Join-Path $buildDirectory 'Tools') -Destination $packageDirectory -Recurse
[IO.Compression.ZipFile]::CreateFromDirectory($packageDirectory, $archive)

Write-Host "Archive: $archive"
Write-Host "SHA-256: $((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash)"
Write-Host "GitHub release: $repository $tag"
Write-Host "Target commit: $commit"
if ((Read-Host 'Publish this release? [y/N]') -notin @('y', 'yes')) {
    Write-Host 'Publication cancelled. The local archive is available at the path above.'
    return
}

$gh = (Get-Command gh.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$releaseArguments = @('release', 'create', $tag, $archive, '--repo', $repository, '--target', $commit,
    '--title', "UDK CLI $Version", '--notes', "Windows x64 build from commit $commit.", '--latest=false')
if ($Version.Contains('-')) { $releaseArguments += '--prerelease' }
& $gh @releaseArguments
if ($LASTEXITCODE -ne 0) { throw "GitHub publication failed. The archive is available at $archive." }