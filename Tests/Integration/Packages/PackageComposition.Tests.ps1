param([string]$CMake, [string]$NuGet = 'nuget.exe', [string]$PackageToolsPackage)

$ErrorActionPreference = 'Stop'
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
if ($PackageToolsPackage) {
    $installedTools = Join-Path $run 'installed-tools'
    [IO.Compression.ZipFile]::ExtractToDirectory($PackageToolsPackage, $installedTools)
    $builder = Join-Path $installedTools 'tools/Build.ps1'
    if (-not (Test-Path -LiteralPath $builder)) { throw 'Installed PackageTools does not contain its entry point.' }
}

function Write-TestJson([string]$Name, $Value) {
    $text = $Value | ConvertTo-Json -Depth 20
    [IO.File]::WriteAllText((Join-Path $external $Name), $text.TrimEnd(), [Text.UTF8Encoding]::new($false))
}
function Read-TestJson([string]$Name) { return Get-Content -LiteralPath (Join-Path $external $Name) -Raw | ConvertFrom-Json }
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

# Планирование работает отдельно от инструментов и в чужом корне репозитория.
$plan = & $builder -RepositoryPath $external -PackagePath Package.json -Plan
if (($plan.Order -join ',') -cne 'Managed,Native,CMake') { throw 'Unexpected project dependency order.' }
foreach ($package in @('PackageTools')) {
    $actual = & $builder -RepositoryPath $repository -PackagePath "Packages/Windows/$package/Package.json" -Plan
    if (-not $actual.Order.Count) { throw "Missing real package plan: $package" }
}
$originalPackage = Read-TestJson 'Package.json'
$package = Read-TestJson 'Package.json'
$package | Add-Member typo $true
Write-TestJson 'Package.json' $package
Expect-Failure { & $builder -RepositoryPath $external -PackagePath Package.json -Plan } 'Unknown field'
$package = Read-TestJson 'Package.json'
$package.PSObject.Properties.Remove('typo')
$package.contents[0].artifact = 'missing'
Write-TestJson 'Package.json' $package
Expect-Failure { & $builder -RepositoryPath $external -PackagePath Package.json -Plan } 'Unknown project artifact'
$package.contents[0].artifact = 'assembly'
$package.contents[0].destination = '../outside'
Write-TestJson 'Package.json' $package
Expect-Failure { & $builder -RepositoryPath $external -PackagePath Package.json -Plan } 'Path escapes'
$package.contents[0].destination = 'lib/net8.0'
$package.schemaVersion = '2'
Write-TestJson 'Package.json' $package
Expect-Failure { & $builder -RepositoryPath $external -PackagePath Package.json -Plan } 'schemaVersion'
Write-TestJson 'Package.json' $originalPackage
$managed = Read-TestJson 'Managed.json'
$managed | Add-Member dependencies @('CMake')
Write-TestJson 'Managed.json' $managed
$native = Read-TestJson 'Native.json'
$native | Add-Member dependencies @('Managed')
Write-TestJson 'Native.json' $native
Expect-Failure { & $builder -RepositoryPath $external -PackagePath Package.json -Plan } 'dependency cycle'
$native.dependencies = @('Unknown')
Write-TestJson 'Native.json' $native
Expect-Failure { & $builder -RepositoryPath $external -PackagePath Package.json -Plan } 'Unknown project dependency'
Copy-Item -LiteralPath (Join-Path $fixture 'Managed.json') -Destination (Join-Path $external 'Managed.json') -Force
Copy-Item -LiteralPath (Join-Path $fixture 'Native.json') -Destination (Join-Path $external 'Native.json') -Force

# Реальная сборка смешанного пакета проверяет все три проектных адаптера и NuGet.
$packagePath = & $builder -RepositoryPath $external -PackagePath Package.json -OutputDirectory (Join-Path $run 'packages') -CMake $CMake -NuGet $NuGet
Assert-PackageEntries $packagePath @('lib/net8.0/Probe.dll', 'include/Probe/Probe.h', 'src/Internal/Hidden.h', 'src/Probe.cpp', 'cmake/Component.json', 'native/share/marker.txt', 'README.txt')
$registry = Read-TestJson 'Projects.json'
$registry.includes += 'Restored.json'
Write-TestJson 'Projects.json' $registry
Write-TestJson 'Restored.json' ([pscustomobject]@{
    schemaVersion = 1
    name = 'Restored'
    adapter = 'nuget-restore'
    id = 'UniversalDevKit.CompositionProbe'
    version = '1.0.0'
    artifacts = [pscustomobject]@{ assembly = [pscustomobject]@{ root = 'package'; path = 'lib/net8.0/Probe.dll' } }
})
$package = Read-TestJson 'Package.json'
$package.name = 'RestoredProbe'
$package.contents = @([pscustomobject]@{ project = 'Restored'; artifact = 'assembly'; destination = 'lib/net8.0' })
Write-TestJson 'Package.json' $package
$delivery = Read-TestJson 'Delivery.json'
$delivery.id = 'UniversalDevKit.CompositionConsumer'
$delivery | Add-Member dependencies @([pscustomobject]@{ id = 'UniversalDevKit.CompositionProbe'; version = '1.0.0' })
Write-TestJson 'Delivery.json' $delivery
$spec = [IO.File]::ReadAllText((Join-Path $external 'Package.nuspec')).Replace('UniversalDevKit.CompositionProbe', $delivery.id).Replace('<group targetFramework="net8.0" />', '<group targetFramework="net8.0">{{DEPENDENCIES}}</group>')
[IO.File]::WriteAllText((Join-Path $external 'Package.nuspec'), $spec.TrimEnd(), [Text.UTF8Encoding]::new($false))
$restoredPackage = & $builder -RepositoryPath $external -PackagePath Package.json -OutputDirectory (Join-Path $run 'restored') -PackageSources (Split-Path -Parent $packagePath) -NuGet $NuGet
Assert-PackageEntries $restoredPackage @('lib/net8.0/Probe.dll')
$archive = [IO.Compression.ZipFile]::OpenRead($restoredPackage)
try {
    $reader = [IO.StreamReader]::new($archive.GetEntry('UniversalDevKit.CompositionConsumer.nuspec').Open())
    try { [xml]$metadata = $reader.ReadToEnd() } finally { $reader.Dispose() }
    $dependency = $metadata.package.metadata.dependencies.group.dependency
    if ($dependency.id -cne 'UniversalDevKit.CompositionProbe' -or $dependency.version -cne '[1.0.0]') { throw 'Exact NuGet dependency was not emitted.' }
} finally { $archive.Dispose() }
$delivery.dependencies += $delivery.dependencies[0]
Write-TestJson 'Delivery.json' $delivery
Expect-Failure { & $builder -RepositoryPath $external -PackagePath Package.json -Plan } 'Duplicate or self NuGet dependency'
Copy-Item -LiteralPath (Join-Path $fixture 'Delivery.json') -Destination (Join-Path $external 'Delivery.json') -Force
Copy-Item -LiteralPath (Join-Path $fixture 'Package.nuspec') -Destination (Join-Path $external 'Package.nuspec') -Force
Write-TestJson 'Package.json' $originalPackage

# Тот же пакет собирается без внешнего реестра; имена проектов локальны для пакета.
$inline = Read-TestJson 'Package.json'
$inline.name = 'InlineProbe'
$inline.projects = [pscustomobject]@{}
foreach ($name in @('Managed', 'Native', 'CMake')) {
    $project = Read-TestJson ($name + '.json')
    $project.PSObject.Properties.Remove('schemaVersion')
    $project.PSObject.Properties.Remove('name')
    $inline.projects | Add-Member -NotePropertyName $name -NotePropertyValue $project
}
Write-TestJson 'Package.json' $inline
$inlinePlan = & $builder -RepositoryPath $external -PackagePath Package.json -Plan
if ($inlinePlan.ProjectScope -cne 'InlineProbe' -or ($inlinePlan.Order -join ',') -cne 'Managed,Native,CMake') { throw 'Incorrect inline project scope or dependency order.' }
$inlinePackage = & $builder -RepositoryPath $external -PackagePath Package.json -OutputDirectory (Join-Path $run 'inline') -CMake $CMake -NuGet $NuGet
Assert-PackageEntries $inlinePackage @('lib/net8.0/Probe.dll', 'include/Probe/Probe.h', 'src/Internal/Hidden.h', 'native/share/marker.txt')
if (-not (Test-Path -LiteralPath (Join-Path $external '!artifacts/projects/windows/udk/InlineProbe/Managed/output/Probe.dll'))) { throw 'Inline project outputs were not isolated by package.' }
$inline.projects.Managed | Add-Member name 'ConflictingName'
Write-TestJson 'Package.json' $inline
Expect-Failure { & $builder -RepositoryPath $external -PackagePath Package.json -Plan } 'Inline project name and schemaVersion are implicit'
$inline.projects.Managed.PSObject.Properties.Remove('name')
$inline.projects.Native | Add-Member dependencies @('CMake')
Write-TestJson 'Package.json' $inline
Expect-Failure { & $builder -RepositoryPath $external -PackagePath Package.json -Plan } 'dependency cycle'
$inline.projects.Native.PSObject.Properties.Remove('dependencies')
$inline.projects.Managed.project = '../outside/Probe.csproj'
Write-TestJson 'Package.json' $inline
Expect-Failure { & $builder -RepositoryPath $external -PackagePath Package.json -Plan } 'Path escapes'
$inline.projects = @('Managed')
Write-TestJson 'Package.json' $inline
Expect-Failure { & $builder -RepositoryPath $external -PackagePath Package.json -Plan } 'projects must be a registry path'
Write-TestJson 'Package.json' $originalPackage
$package = Read-TestJson 'Package.json'
$package.contents = @($package.contents[1], $package.contents[1])
Write-TestJson 'Package.json' $package
Expect-Failure { & $builder -RepositoryPath $external -PackagePath Package.json -OutputDirectory (Join-Path $run 'collision') -NuGet $NuGet } 'Package content collision'
$package.contents = @($originalPackage.contents[1])
$native = Read-TestJson 'Native.json'
$native.artifacts.sources.path = 'missing'
Write-TestJson 'Native.json' $native
Write-TestJson 'Package.json' $package
Expect-Failure { & $builder -RepositoryPath $external -PackagePath Package.json -OutputDirectory (Join-Path $run 'missing') -NuGet $NuGet } 'Missing path'

# Выбор доставки ограничивает граф проектов; версия может читаться из properties.
Write-TestJson 'Package.json' $originalPackage
$package = Read-TestJson 'Package.json'
$package.deliveries | Add-Member Android 'Maven.json'
Write-TestJson 'Maven.json' ([pscustomobject]@{ schemaVersion=1; adapter='maven-repository'; groupId='org.probe'; artifactId='probe' })
foreach ($content in $package.contents) { $content | Add-Member deliveries @('NuGet') }
$package.contents += [pscustomobject]@{ project='Native'; artifact='sources'; destination='.'; deliveries=@('Android') }
[IO.File]::WriteAllText((Join-Path $external 'version.properties'), 'packageVersion=1.2.3', [Text.UTF8Encoding]::new($false))
$package.versionSource = [pscustomobject]@{ path='version.properties'; format='properties'; property='packageVersion' }
Write-TestJson 'Package.json' $package
$selected = & $builder -RepositoryPath $external -PackagePath Package.json -Delivery Android -Plan
if ($selected.Version -cne '1.2.3' -or ($selected.Order -join ',') -cne 'Native') { throw 'Delivery filtering or properties version failed.' }
$package | Add-Member releaseDependencies @([pscustomobject]@{ package='Package.json'; delivery='Android'; when=@('NuGet') })
Write-TestJson 'Package.json' $package
$selected = & $builder -RepositoryPath $external -PackagePath Package.json -Delivery NuGet -Plan
if ($selected.ReleaseDependencies.Count -ne 1 -or $selected.ReleaseDependencies[0].DeliveryName -cne 'Android') { throw 'Conditional release dependency was not selected.' }
$package.releaseDependencies[0].when = @('Android')
Write-TestJson 'Package.json' $package
Expect-Failure { & $builder -RepositoryPath $external -PackagePath Package.json -Delivery Android -Plan } 'Package release dependency cycle'

Write-Host 'PASS: declarative package composition, external repository and validation.'