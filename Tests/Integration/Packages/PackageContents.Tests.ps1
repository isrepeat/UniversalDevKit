param([string]$UdkCliDirectory, [string]$NuGet = 'nuget.exe')

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../../Infrastructure/WriteTestManifest.ps1')
$repository = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
. (Join-Path $repository 'Scripts/PowerShell/ArtifactDirectories.ps1')
$run = Reset-UdkArtifactDirectory -Root (Join-Path $repository '!artifacts/tests') -Path (Join-Path $repository '!artifacts/tests/PackageContents.Tests')
$external = Join-Path $run 'external'
[void][IO.Directory]::CreateDirectory($external)
$builder = Join-Path $repository 'Packages/Build/Build.ps1'
Add-Type -AssemblyName System.IO.Compression.FileSystem
if ($UdkCliDirectory) {
    $builder = Join-Path $UdkCliDirectory 'Tools/PackageTools/Build.ps1'
}
foreach ($file in @('Delivery.xml', 'Package.nuspec')) {
    Copy-Item -LiteralPath (Join-Path $repository "Tests/Fixtures/PackageComposition/$file") -Destination $external
}
foreach ($file in @('Top.dll', 'Core/A.dll', 'Core/ATests.dll', 'Extensions/B.dll', 'Extensions/A.dll', 'Nested/Deep/C.DLL', 'Core/data.json')) {
    $target = Join-Path $external "input/$file"
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $target))
    [IO.File]::WriteAllText($target, $file, [Text.UTF8Encoding]::new($false))
}

function Save-ContentsXml([string]$Name, $Value) {
    [IO.File]::WriteAllText((Join-Path $external $Name), (ConvertTo-TestManifestXml $Value (Get-TestManifestRoot $Name)), [Text.UTF8Encoding]::new($false))
}
function Set-ContentsPackage($Content) {
    $project = [ordered]@{
        adapter = 'files'
        mappings = @(@{ source = 'input'; destination = '.' })
    }
    Save-ContentsXml 'Package.xml' @{
        schemaVersion = 2
        name = 'ContentsProbe'
        version = '1.0.0'
        projects = @{ files = $project }
        contents = @($Content)
        deliveries = @{ NuGet = 'Delivery.xml' }
    }
}
function Assert-ContentsPackage([string[]]$Expected) {
    $package = & $builder -RepositoryPath $external -PackagePath Package.xml -OutputDirectory (Join-Path $run 'packages') -NuGet $NuGet
    $archive = [IO.Compression.ZipFile]::OpenRead($package)
    try {
        $actual = @($archive.Entries.FullName | ForEach-Object { $_.Replace('\', '/') } | Where-Object { $_ -like 'selected/*' } | Sort-Object)
        $expectedPaths = @($Expected | ForEach-Object { 'selected/' + $_ } | Sort-Object)
        if (($actual -join ';') -cne ($expectedPaths -join ';')) {
            throw "Unexpected contents. Expected: $expectedPaths; actual: $actual"
        }
        foreach ($name in $actual) {
            $reader = [IO.StreamReader]::new($archive.GetEntry($name).Open())
            try {
                $text = $reader.ReadToEnd()
                if (-not (Test-Path -LiteralPath (Join-Path $external "input/$text") -PathType Leaf)) {
                    throw "Unexpected file data: $name"
                }
            } finally {
                $reader.Dispose()
            }
        }
    } finally {
        $archive.Dispose()
    }
}
function Expect-ContentsFailure([scriptblock]$Action, [string]$Pattern) {
    $message = $null
    try { & $Action | Out-Null } catch { $message = $_.Exception.Message }
    if (-not $message -or $message -notmatch $Pattern) {
        throw "Expected '$Pattern', got '$message'."
    }
}

# Patterns are relative to the selected root; ** also includes top-level files.
$content = @{ project = 'files'; destination = 'selected'; include = @('**/*.dll'); exclude = @('**/*Tests.dll', 'Extensions/A.dll') }
Set-ContentsPackage $content
Assert-ContentsPackage @('Top.dll', 'Core/A.dll', 'Extensions/B.dll', 'Nested/Deep/C.DLL')
$content.include = @('*.dll')
Set-ContentsPackage $content
Assert-ContentsPackage @('Top.dll')
$content.include = @('Nested/**/*.dll')
Set-ContentsPackage $content
Assert-ContentsPackage @('Nested/Deep/C.DLL')
$content.include = @('Core/**/*.dll')
Set-ContentsPackage $content
Assert-ContentsPackage @('Core/A.dll')

# A single selection can flatten files from different directories.
$content.include = @('Core/A.dll', 'Extensions/B.dll', 'Core/*.dll')
$content.preserveHierarchy = $false
Set-ContentsPackage $content
Assert-ContentsPackage @('A.dll', 'B.dll')
$content.include = @('Core\A.dll', 'Extensions\B.dll')
$content.root = 'output'
Set-ContentsPackage $content
Assert-ContentsPackage @('A.dll', 'B.dll')

# A subdirectory defines the hierarchy base.
$content = @{ project = 'files'; path = 'Core'; include = @('*.dll'); exclude = @('*Tests.dll'); destination = 'selected'; preserveHierarchy = $true }
Set-ContentsPackage $content
Assert-ContentsPackage @('A.dll')
$content = @{ project = 'files'; path = 'Top.dll'; destination = 'selected'; rename = @{ 'Top.dll' = 'Renamed.dll' } }
Set-ContentsPackage $content
Assert-ContentsPackage @('Renamed.dll')

# Omitting filters preserves the previous whole-tree copy behavior.
$content = @{ project = 'files'; destination = 'selected' }
Set-ContentsPackage $content
Assert-ContentsPackage @('Top.dll', 'Core/A.dll', 'Core/ATests.dll', 'Extensions/B.dll', 'Extensions/A.dll', 'Nested/Deep/C.DLL', 'Core/data.json')
$content.exclude = @('**/*.dll')
Set-ContentsPackage $content
Assert-ContentsPackage @('Core/data.json')
$content.exclude = @()
Set-ContentsPackage $content
Assert-ContentsPackage @('Top.dll', 'Core/A.dll', 'Core/ATests.dll', 'Extensions/B.dll', 'Extensions/A.dll', 'Nested/Deep/C.DLL', 'Core/data.json')
$content.Remove('exclude')

# Empty selections and collisions must fail instead of producing incomplete packages.
$build = { & $builder -RepositoryPath $external -PackagePath Package.xml -OutputDirectory (Join-Path $run 'packages') -NuGet $NuGet }
$plan = { & $builder -RepositoryPath $external -PackagePath Package.xml -Plan }
$content.include = @('missing/**/*.dll')
Set-ContentsPackage $content
Expect-ContentsFailure $build 'No files selected'
$content.include = @('**/*.dll')
$content.exclude = @('**')
Set-ContentsPackage $content
Expect-ContentsFailure $build 'No files selected'
$content.Remove('exclude')
$content.include = @('Core/A.dll', 'Extensions/A.dll')
$content.preserveHierarchy = $false
Set-ContentsPackage $content
Expect-ContentsFailure $build 'Package content collision'
$content.path = 'Top.dll'
Set-ContentsPackage $content
Expect-ContentsFailure $build 'require a directory'
$content.Remove('path')
foreach ($include in @('*.dll', $null, @(), @('../*.dll'), @('/**'), @('C:/*.dll'), @('x/**bad/*.dll'), @('**/./*.dll'), @('**/?.dll'), @('**/[a].dll'), @('**//*.dll'))) {
    $content.include = $include
    Set-ContentsPackage $content
    Expect-ContentsFailure $plan 'patterns|pattern|Expected nested elements in Includes'
}
$content.include = @('**/*.dll')
$content.preserveHierarchy = 'no'
Set-ContentsPackage $content
Expect-ContentsFailure $plan 'Invalid XML boolean'
$content.preserveHierarchy = $true
$content.root = 'install'
Set-ContentsPackage $content
Expect-ContentsFailure $plan 'Unknown project root'
$content.root = 'output'
$content.artifact = 'all'
Set-ContentsPackage $content
Expect-ContentsFailure $plan "Unknown field 'artifact'"
$content.Remove('artifact')
Set-ContentsPackage $content
$obsolete = Read-UdkManifest (Join-Path $external 'Package.xml') 'Package'
$obsolete.projects.files | Add-Member artifacts ([pscustomobject]@{ all = [pscustomobject]@{ root = 'output'; path = '.' } })
Save-ContentsXml 'Package.xml' $obsolete
Expect-ContentsFailure $plan "Unknown field 'artifacts'"
$content.rename = 'all.dll'
Set-ContentsPackage $content
Expect-ContentsFailure $plan 'Expected nested entries in Rename'
$content.Remove('rename')

# External project registries use the same direct selection contract.
$content = @{ project = 'files'; destination = 'selected'; include = @('*.dll') }
Set-ContentsPackage $content
Save-ContentsXml 'Project.xml' @{
    schemaVersion = 1
    name = 'files'
    adapter = 'files'
    mappings = @(@{ source = 'input'; destination = '.' })
}
Save-ContentsXml 'Registry.xml' @{ schemaVersion = 1; includes = @('Project.xml') }
$package = Read-UdkManifest (Join-Path $external 'Package.xml') 'Package'
$package.projects = 'Registry.xml'
Save-ContentsXml 'Package.xml' $package
Assert-ContentsPackage @('Top.dll')
$obsoleteProject = Read-UdkManifest (Join-Path $external 'Project.xml') 'Project'
$obsoleteProject | Add-Member artifacts ([pscustomobject]@{})
Save-ContentsXml 'Project.xml' $obsoleteProject
Expect-ContentsFailure $plan "Unknown field 'artifacts'"

# CMake roots are adapter-specific and must be selected explicitly.
$package.projects = @{
    native = @{
        adapter = 'cmake-install'
        sourceDirectory = 'input'
        generator = 'Visual Studio 18 2026'
        architecture = 'x64'
        configurations = @('Release')
        parallel = 1
        variables = @{}
    }
}
$package.contents = @(@{ project = 'native'; root = 'install'; destination = 'selected'; include = @('**/*.dll') })
Save-ContentsXml 'Package.xml' $package
$selected = & $plan
if (($selected.Order -join ',') -cne 'native') { throw 'CMake direct root was not planned.' }
$package.contents[0].Remove('root')
Save-ContentsXml 'Package.xml' $package
Expect-ContentsFailure $plan 'Unknown project root'
# Repository directories use the same selection and rename rules without build projects.
$content = @{ source = 'input'; include = @('**/*.dll'); exclude = @('**/*Tests.dll', 'Extensions/A.dll'); destination = 'selected'; rename = @{ 'Core/A.dll' = 'Renamed.dll' } }
Set-ContentsPackage $content
$package = Read-UdkManifest (Join-Path $external 'Package.xml') 'Package'
$package.projects = [pscustomobject]@{}
Save-ContentsXml 'Package.xml' $package
$selected = & $plan
if ($selected.Order.Count) { throw 'Repository contents unexpectedly selected a build project.' }
Assert-ContentsPackage @('Top.dll', 'Core/Renamed.dll', 'Extensions/B.dll', 'Nested/Deep/C.DLL')
$content.preserveHierarchy = $false
Set-ContentsPackage $content
Assert-ContentsPackage @('Top.dll', 'Renamed.dll', 'B.dll', 'C.DLL')
$content.source = '.'
$content.include = @('input/Core/A.dll', 'input/Extensions/B.dll')
$content.exclude = @()
$content.rename = @{ 'input\core\a.DLL' = 'First.dll' }
Set-ContentsPackage $content
Assert-ContentsPackage @('First.dll', 'B.dll')
$content = @{ source = 'input/Core'; destination = 'selected'; exclude = @('*.json', '*Tests.dll') }
Set-ContentsPackage $content
Assert-ContentsPackage @('A.dll')

# Both source kinds support map-based renames and reject ambiguous target names.
$content = @{ project = 'files'; destination = 'selected'; include = @('Core/A.dll', 'Extensions/A.dll'); preserveHierarchy = $false; rename = @{ 'Extensions/A.dll' = 'Other.dll' } }
Set-ContentsPackage $content
Assert-ContentsPackage @('A.dll', 'Other.dll')
$content = @{ source = 'input'; destination = 'selected'; include = @('Core/A.dll', 'Extensions/B.dll'); preserveHierarchy = $false; rename = @{ 'Extensions/B.dll' = 'A.dll' } }
Set-ContentsPackage $content
Expect-ContentsFailure $build 'Package content collision'
$content.rename = @{ 'missing.dll' = 'Other.dll' }
Set-ContentsPackage $content
Expect-ContentsFailure $build 'Unused rename source'
$content.rename = @{ 'Extensions/B.dll' = 'Other.dll' }
$content.exclude = @('Extensions/**')
Set-ContentsPackage $content
Expect-ContentsFailure $build 'Unused rename source'
$content.Remove('exclude')
foreach ($rename in @(
    'Other.dll'
    @{ '../A.dll' = 'Other.dll' }
    @{ '*.dll' = 'Other.dll' }
    @{ 'Core/A.dll' = '../Other.dll' }
    @{ 'Core/A.dll' = 'sub/Other.dll' }
    @{ 'Core/A.dll' = 'C:Other.dll' }
    @{ 'Core/A.dll' = '' }
    @{ 'Core/A.dll' = '.' }
    @{ 'Core/A.dll' = 'First.dll'; 'Core\A.dll' = 'Second.dll' }
)) {
    $content.rename = $rename
    Set-ContentsPackage $content
    Expect-ContentsFailure $plan 'rename|pattern'
}
$content.Remove('rename')
$content.include = @()
Set-ContentsPackage $content
Expect-ContentsFailure $plan 'include must not be empty'
$content.include = @('**/*.dll')
$content.source = '../outside'
Set-ContentsPackage $content
Expect-ContentsFailure $plan 'Path escapes'
$content.source = 'input/Top.dll'
Set-ContentsPackage $content
Expect-ContentsFailure $plan 'must reference a directory'
$content.source = 'input'
$content.project = 'files'
Set-ContentsPackage $content
Expect-ContentsFailure $plan 'Unknown field'
$content.Remove('project')
$content.root = 'output'
Set-ContentsPackage $content
Expect-ContentsFailure $plan 'Unknown field'
$content.Remove('root')
$content.file = 'input/Top.dll'
Set-ContentsPackage $content
Expect-ContentsFailure $plan "Unknown field 'file'"
Write-Host 'PASS: project and repository contents, patterns, renames, hierarchy and validation.'