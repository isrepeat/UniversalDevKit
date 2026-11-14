param([string]$CMake, [string]$NuGet = 'nuget.exe', [string]$UdkCliDirectory)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../../Infrastructure/WriteTestManifest.ps1')
$env:DOTNET_CLI_UI_LANGUAGE = 'en-US'
$env:VSLANG = '1033'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)
$repository = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$builder = Join-Path $repository 'Packages/Build/Build.ps1'
. (Join-Path $repository 'Scripts/PowerShell/ArtifactDirectories.ps1')
$run = Reset-UdkArtifactDirectory -Root (Join-Path $repository '!artifacts/tests') -Path (Join-Path $repository '!artifacts/tests/PackageComposition.Tests')
$fixture = Join-Path $repository 'Tests/Fixtures/PackageComposition'
$external = Join-Path $run 'external'
[void][IO.Directory]::CreateDirectory($external)
Copy-Item -Path (Join-Path $fixture '*') -Destination $external -Recurse
Add-Type -AssemblyName System.IO.Compression.FileSystem
if ($UdkCliDirectory) {
    $builder = Join-Path $UdkCliDirectory 'Tools/PackageTools/Build.ps1'
    if (-not (Test-Path -LiteralPath $builder)) { throw 'Installed PackageTools does not contain its entry point.' }
}

function Write-TestXml([string]$Name, $Value) {
    $text = ConvertTo-TestManifestXml $Value (Get-TestManifestRoot $Name)
    [IO.File]::WriteAllText((Join-Path $external $Name), $text.TrimEnd(), [Text.UTF8Encoding]::new($false))
}
function Read-TestXml([string]$Name) { Read-UdkManifest (Join-Path $external $Name) (Get-TestManifestRoot $Name) }
function Expect-Failure([scriptblock]$Action, [string]$Pattern) {
    $caught = $null
    try { & $Action | Out-Null } catch { $caught = $_.Exception.Message }
    if (-not $caught -or $caught -notmatch $Pattern) { throw "Expected '$Pattern', got '$caught'." }
    Write-Host "Rejected as expected: $Pattern"
}
function Assert-PackageEntries([string]$Path, [string[]]$Required) {
    $archive = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $names = @($archive.Entries | ForEach-Object { $_.FullName.Replace('\', '/') })
        foreach ($name in $Required) { if ($name -cnotin $names) { throw "Missing package entry '$name': $Path" } }
        if (@($names | Where-Object { $_ -match '(^|/)(obj|staging|!artifacts)/' }).Count) { throw 'Package leaked build directories.' }
        if ($names -contains 'include/Probe/Internal/Hidden.h') { throw 'Internal header leaked into public include tree.' }
    } finally { $archive.Dispose() }
}

# Planning runs without build tools and works from a separate repository root.
$plan = & $builder -RepositoryPath $external -PackagePath Package.xml -Plan
if (($plan.Order -join ',') -cne 'Managed,Native,CMake') { throw 'Unexpected project dependency order.' }
if ($plan.Version -cne '1.0.0' -or ($plan.AbiVersion -isnot [int] -and $plan.AbiVersion -isnot [long]) -or $plan.AbiVersion -ne 0) { throw 'JSON reference resolution failed.' }
foreach ($package in @('XamlCompiler')) {
    $actual = & $builder -RepositoryPath $repository -PackagePath "Packages/Windows/$package/Package.xml" -Plan
    if (-not $actual.Order.Count) { throw "Missing real package plan: $package" }
}
$originalPackage = Read-TestXml 'Package.xml'
$package = Read-TestXml 'Package.xml'
$package | Add-Member typo $true
Write-TestXml 'Package.xml' $package
Expect-Failure { & $builder -RepositoryPath $external -PackagePath Package.xml -Plan } 'Unknown field'
$package = Read-TestXml 'Package.xml'
$package.PSObject.Properties.Remove('typo')
$package.contents[0].root = 'missing'
Write-TestXml 'Package.xml' $package
Expect-Failure { & $builder -RepositoryPath $external -PackagePath Package.xml -Plan } 'Unknown project root'
$package.contents[0].root = 'output'
$package.contents[0].destination = '../outside'
Write-TestXml 'Package.xml' $package
Expect-Failure { & $builder -RepositoryPath $external -PackagePath Package.xml -Plan } 'Path escapes'
$package.contents[0].destination = 'lib/net8.0'
$package.schemaVersion = 'two'
Write-TestXml 'Package.xml' $package
Expect-Failure { & $builder -RepositoryPath $external -PackagePath Package.xml -Plan } 'schemaVersion'
Write-TestXml 'Package.xml' $originalPackage
$managed = Read-TestXml 'Managed.xml'
$managed | Add-Member dependencies @('CMake')
Write-TestXml 'Managed.xml' $managed
$native = Read-TestXml 'Native.xml'
$native | Add-Member dependencies @('Managed')
Write-TestXml 'Native.xml' $native
Expect-Failure { & $builder -RepositoryPath $external -PackagePath Package.xml -Plan } 'dependency cycle'
$native.dependencies = @('Unknown')
Write-TestXml 'Native.xml' $native
Expect-Failure { & $builder -RepositoryPath $external -PackagePath Package.xml -Plan } 'Unknown project dependency'
Copy-Item -LiteralPath (Join-Path $fixture 'Managed.xml') -Destination (Join-Path $external 'Managed.xml') -Force
Copy-Item -LiteralPath (Join-Path $fixture 'Native.xml') -Destination (Join-Path $external 'Native.xml') -Force

# Building a mixed package exercises all three project adapters and NuGet.
$packagePath = & $builder -RepositoryPath $external -PackagePath Package.xml -OutputDirectory (Join-Path $run 'packages') -CMake $CMake -NuGet $NuGet
Assert-PackageEntries $packagePath @('lib/net8.0/Probe.dll', 'include/Probe/Probe.h', 'src/Internal/Hidden.h', 'src/Probe.cpp', 'cmake/Component.json', 'native/share/marker.txt', 'README.txt')
$registry = Read-TestXml 'Projects.xml'
$registry.includes += 'Restored.xml'
Write-TestXml 'Projects.xml' $registry
Write-TestXml 'Restored.xml' ([pscustomobject]@{
    schemaVersion = 1
    name = 'Restored'
    adapter = 'nuget-restore'
    id = 'UniversalDevKit.CompositionProbe'
    version = '1.0.0'
})
$package = Read-TestXml 'Package.xml'
$package.name = 'RestoredProbe'
$package.contents = @([pscustomobject]@{ project = 'Restored'; root = 'package'; path = 'lib/net8.0/Probe.dll'; destination = 'lib/net8.0' })
Write-TestXml 'Package.xml' $package
$delivery = Read-TestXml 'Delivery.xml'
$delivery.id = 'UniversalDevKit.CompositionConsumer'
$delivery | Add-Member dependencies @([pscustomobject]@{ id = 'UniversalDevKit.CompositionProbe'; version = '1.0.0' })
Write-TestXml 'Delivery.xml' $delivery
$spec = [IO.File]::ReadAllText((Join-Path $external 'Package.nuspec')).Replace('UniversalDevKit.CompositionProbe', $delivery.id).Replace('<group targetFramework="net8.0" />', '<group targetFramework="net8.0">{{DEPENDENCIES}}</group>')
[IO.File]::WriteAllText((Join-Path $external 'Package.nuspec'), $spec.TrimEnd(), [Text.UTF8Encoding]::new($false))
$restoredPackage = & $builder -RepositoryPath $external -PackagePath Package.xml -OutputDirectory (Join-Path $run 'restored') -PackageSources (Split-Path -Parent $packagePath) -NuGet $NuGet
Assert-PackageEntries $restoredPackage @('lib/net8.0/Probe.dll')
$archive = [IO.Compression.ZipFile]::OpenRead($restoredPackage)
try {
    $reader = [IO.StreamReader]::new($archive.GetEntry('UniversalDevKit.CompositionConsumer.nuspec').Open())
    try { [xml]$metadata = $reader.ReadToEnd() } finally { $reader.Dispose() }
    $dependency = $metadata.package.metadata.dependencies.group.dependency
    if ($dependency.id -cne 'UniversalDevKit.CompositionProbe' -or $dependency.version -cne '[1.0.0]') { throw 'Exact NuGet dependency was not emitted.' }
} finally { $archive.Dispose() }
$delivery.dependencies += $delivery.dependencies[0]
Write-TestXml 'Delivery.xml' $delivery
Expect-Failure { & $builder -RepositoryPath $external -PackagePath Package.xml -Plan } 'Duplicate or self NuGet dependency'
Copy-Item -LiteralPath (Join-Path $fixture 'Delivery.xml') -Destination (Join-Path $external 'Delivery.xml') -Force
Copy-Item -LiteralPath (Join-Path $fixture 'Package.nuspec') -Destination (Join-Path $external 'Package.nuspec') -Force
Write-TestXml 'Package.xml' $originalPackage

# Build the same package without an external registry. Project names are package-local.
$inline = Read-TestXml 'Package.xml'
$inline.name = 'InlineProbe'
$inline.projects = [pscustomobject]@{}
foreach ($name in @('Managed', 'Native', 'CMake')) {
    $project = Read-TestXml ($name + '.xml')
    $project.PSObject.Properties.Remove('schemaVersion')
    $project.PSObject.Properties.Remove('name')
    $inline.projects | Add-Member -NotePropertyName $name -NotePropertyValue $project
}
Write-TestXml 'Package.xml' $inline
$inlinePlan = & $builder -RepositoryPath $external -PackagePath Package.xml -Plan
if ($inlinePlan.ProjectScope -cne 'InlineProbe' -or ($inlinePlan.Order -join ',') -cne 'Managed,Native,CMake') { throw 'Incorrect inline project scope or dependency order.' }
$inlinePackage = & $builder -RepositoryPath $external -PackagePath Package.xml -OutputDirectory (Join-Path $run 'inline') -CMake $CMake -NuGet $NuGet
Assert-PackageEntries $inlinePackage @('lib/net8.0/Probe.dll', 'include/Probe/Probe.h', 'src/Internal/Hidden.h', 'native/share/marker.txt')
if (-not (Test-Path -LiteralPath (Join-Path $external '!artifacts/package-build/InlineProbe/Managed/output/Probe.dll'))) { throw 'Inline project outputs were not isolated by package.' }
$inline.projects.CMake | Add-Member buildDirectory '!artifacts/custom-build'
Write-TestXml 'Package.xml' $inline
Expect-Failure { & $builder -RepositoryPath $external -PackagePath Package.xml -Plan } 'Unknown field'
$inline.projects.CMake.PSObject.Properties.Remove('buildDirectory')
$inline.projects.Managed | Add-Member name 'ConflictingName'
Write-TestXml 'Package.xml' $inline
Expect-Failure { & $builder -RepositoryPath $external -PackagePath Package.xml -Plan } 'Inline project name and schemaVersion are implicit'
$inline.projects.Managed.PSObject.Properties.Remove('name')
$inline.projects.Native | Add-Member dependencies @('CMake')
Write-TestXml 'Package.xml' $inline
Expect-Failure { & $builder -RepositoryPath $external -PackagePath Package.xml -Plan } 'dependency cycle'
$inline.projects.Native.PSObject.Properties.Remove('dependencies')
$inline.projects.Managed.project = '../outside/Probe.csproj'
Write-TestXml 'Package.xml' $inline
Expect-Failure { & $builder -RepositoryPath $external -PackagePath Package.xml -Plan } 'Path escapes'
$inline.projects = @('Managed')
Write-TestXml 'Package.xml' $inline
Expect-Failure { & $builder -RepositoryPath $external -PackagePath Package.xml -Plan } 'Invalid or duplicate entry in Projects'
Write-TestXml 'Package.xml' $originalPackage
$package = Read-TestXml 'Package.xml'
$package.contents = @($package.contents[1], $package.contents[1])
Write-TestXml 'Package.xml' $package
Expect-Failure { & $builder -RepositoryPath $external -PackagePath Package.xml -OutputDirectory (Join-Path $run 'collision') -NuGet $NuGet } 'Package content collision'
$package.contents = @($originalPackage.contents[1])
$package.contents[0] | Add-Member path 'missing'
Write-TestXml 'Package.xml' $package
Expect-Failure { & $builder -RepositoryPath $external -PackagePath Package.xml -OutputDirectory (Join-Path $run 'missing') -NuGet $NuGet } 'Missing path'

# Delivery selection limits the project graph. An explicit version overrides the reference.
Write-TestXml 'Package.xml' $originalPackage
$package = Read-TestXml 'Package.xml'
$package.deliveries | Add-Member Android 'Maven.xml'
Write-TestXml 'Maven.xml' ([pscustomobject]@{ schemaVersion=1; adapter='maven-repository'; groupId='org.probe'; artifactId='probe' })
foreach ($content in $package.contents) { $content | Add-Member deliveries @('NuGet') }
$package.contents += [pscustomobject]@{ project='Native'; root='output'; destination='.'; deliveries=@('Android') }
$package.version = '1.2.3'
Write-TestXml 'Package.xml' $package
$selected = & $builder -RepositoryPath $external -PackagePath Package.xml -Delivery Android -Plan
if ($selected.Version -cne '1.2.3' -or ($selected.Order -join ',') -cne 'Native') { throw 'Delivery filtering or literal version failed.' }
$package | Add-Member releaseDependencies @([pscustomobject]@{ package='Package.xml'; delivery='Android'; when=@('NuGet') })
Write-TestXml 'Package.xml' $package
$selected = & $builder -RepositoryPath $external -PackagePath Package.xml -Delivery NuGet -Plan
if ($selected.ReleaseDependencies.Count -ne 1 -or $selected.ReleaseDependencies[0].DeliveryName -cne 'Android') { throw 'Conditional release dependency was not selected.' }
$package.releaseDependencies[0].when = @('Android')
Write-TestXml 'Package.xml' $package
Expect-Failure { & $builder -RepositoryPath $external -PackagePath Package.xml -Delivery Android -Plan } 'Package release dependency cycle'

Write-Host 'PASS: declarative package composition, external repository and validation.'