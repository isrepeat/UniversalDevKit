param(
    [string]$CMake,
    [string]$NuGet = 'nuget.exe',
    [Parameter(Mandatory = $true)][string]$LicenseFile,
    [string]$OutputDirectory,
    [string[]]$Components,
    [string]$Generator = 'Visual Studio 18 2026',
    [string]$RepositoryPath = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
)

$env:DOTNET_CLI_UI_LANGUAGE = 'en-US'
$env:VSLANG = '1033'

$ErrorActionPreference = 'Stop'

# Align console and native pipeline encodings in Windows PowerShell 5.1.
$utf8Encoding = [Text.UTF8Encoding]::new($false)
[Console]::InputEncoding = $utf8Encoding
[Console]::OutputEncoding = $utf8Encoding
$OutputEncoding = $utf8Encoding

# 1. Locate tools and the release directory; read the shared version.
$repository = (Resolve-Path -LiteralPath $RepositoryPath).Path
if (-not $CMake) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    $CMake = @(& $vswhere -latest -products '*' -find 'Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe')[0]
}
if (-not $CMake -or -not (Get-Command $CMake -ErrorAction SilentlyContinue)) { throw 'CMake is required.' }
$license = (Resolve-Path -LiteralPath $LicenseFile).Path
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repository ('!artifacts/packages/nuget/' + [Guid]::NewGuid().ToString('N')) }
$output = [IO.Path]::GetFullPath($OutputDirectory)
[void][IO.Directory]::CreateDirectory($output)
$version = (Get-Content (Join-Path $repository 'Version.json') -Raw | ConvertFrom-Json).version

# 2. Validate the registry and expand selected component dependencies.
$connection = Join-Path $repository 'Scripts/PowerShell/Modules/Module.Udk.Connection/Private'
. (Join-Path $connection 'Requirements.ps1')
. (Join-Path $connection 'ComponentRegistry.ps1')
. (Join-Path $connection 'ConnectionPlan.ps1')
$registry = Get-UdkComponentRegistry $repository
if (-not $Components) { $Components = @($registry.Keys | Sort-Object) }
$selected = @(Resolve-UdkComponents $Components $registry)
$hasBinaries = @($selected | Where-Object { $registry[$_].Kind -ne 'headerOnly' }).Count -gt 0

# Package definitions explicitly reference components through the component adapter.
$packages = @{}
$packageIds = @{}
foreach ($definitionFile in Get-ChildItem -LiteralPath (Join-Path $repository 'Packages') -Filter Package.json -File -Recurse) {
    $definition = Get-Content -LiteralPath $definitionFile.FullName -Raw | ConvertFrom-Json
    if ($definition.schemaVersion -ne 1 -or -not $definition.name -or -not $definition.versionSource) { throw "Invalid package definition: $($definitionFile.FullName)" }
    foreach ($field in $definition.PSObject.Properties.Name) {
        if ($field -notin @('schemaVersion', 'name', 'component', 'versionSource', 'deliveries')) { throw "Unknown package field: $field" }
    }
    if (-not $definition.deliveries.NuGet) { continue }
    $delivery = Get-Content -LiteralPath (Join-Path $definitionFile.DirectoryName $definition.deliveries.NuGet) -Raw | ConvertFrom-Json
    # This adapter builds Windows components; other products use other adapters.
    if ($delivery.adapter -ne 'component' -or 'Windows' -notin $delivery.supportedPlatforms) { continue }
    if ($delivery.schemaVersion -ne 1 -or -not $definition.component -or $delivery.id -notmatch '^[A-Za-z0-9_.-]+$') { throw "Unsupported NuGet delivery: $($definitionFile.FullName)" }
    foreach ($field in $delivery.PSObject.Properties.Name) {
        if ($field -notin @('schemaVersion', 'adapter', 'id', 'supportedPlatforms', 'integration', 'nuspec')) { throw "Unknown delivery field: $field" }
    }
    $packageVersion = (Get-Content -LiteralPath (Join-Path $definitionFile.DirectoryName $definition.versionSource) -Raw | ConvertFrom-Json).version
    if ($packageVersion -ne $version) { throw "Component package must use the UDK release version: $($definition.name)" }
    if ($packages.ContainsKey($definition.component) -or $packageIds.ContainsKey($delivery.id)) { throw "Duplicate component package or package ID: $($definition.name)" }
    if (-not $delivery.integration.targets) { throw "Package requires its own targets: $($definition.name)" }
    $deliveryDirectory = Split-Path -Parent (Join-Path $definitionFile.DirectoryName $definition.deliveries.NuGet)
    $integration = @{}
    if (-not $delivery.nuspec) { throw "Package requires its own nuspec: $($definition.name)" }
    $nuspecPath = [IO.Path]::GetFullPath((Join-Path $deliveryDirectory $delivery.nuspec))
    $packagePrefix = $definitionFile.DirectoryName.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $nuspecPath.StartsWith($packagePrefix, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $nuspecPath -PathType Leaf)) { throw "Invalid package nuspec: $nuspecPath" }
    foreach ($kind in @('props', 'targets')) {
        if (-not $delivery.integration.$kind) { continue }
        $integrationPath = [IO.Path]::GetFullPath((Join-Path $deliveryDirectory $delivery.integration.$kind))
        $packagePrefix = $definitionFile.DirectoryName.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
        if (-not $integrationPath.StartsWith($packagePrefix, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $integrationPath -PathType Leaf)) { throw "Invalid package integration file: $integrationPath" }
        $integration[$kind] = $integrationPath
    }
    $packages[$definition.component] = [pscustomobject]@{ Name = $definition.name; Id = $delivery.id; Directory = $definitionFile.DirectoryName; Integration = $integration; Nuspec = $nuspecPath }
    $packageIds[$delivery.id] = $true
}
foreach ($name in $selected) {
    if (-not $packages.ContainsKey($name)) { throw "No NuGet package definition for component: $name" }
}

# 3. Calculate linker inputs, public requirements and DLLs for every supported mode.
# Connect and packaging use the same graph resolver and registry names.
$graphs = @{}
foreach ($name in $selected) {
    $modes = if ($registry[$name].Kind -eq 'headerOnly') { @('Shared') } elseif ($registry[$name].StateScope -eq 'process') { @('Dynamic') } else { @('Static', 'Dynamic') }
    foreach ($mode in $modes) { $graphs["$name.$mode"] = Resolve-UdkLinkageGraph @($name) @{ $name = $mode } $registry }
}

# Return MSBuild expressions evaluated after restore on the consumer machine.
function PackageRoot([string]$Name) { return '$(__UniversalDevKit' + $Name + 'PackageRoot)' }
function RootCondition([string]$Name, [string]$Mode) {
    # Restored dependencies become roots only when explicitly selected by the consumer.
    return "`$([System.String]::Copy(';`$(UniversalDevKitComponents);').Contains(';$Name;')) and '`$(UniversalDevKit${Name}Linkage)' == '$Mode'"
}
function GetEntry($Record, [string]$Name, [string]$Mode) {
    # Use actual artifact names, including Debug suffixes.
    $entries = @($Record.Metadata.components | Where-Object { $_.name -ceq $Name -and $_.variant -ceq $Mode })
    if ($entries.Count -ne 1) { throw "Missing packaged variant: $Name.$Mode" }
    return $entries[0]
}
function GetDll($Record, [string]$Name) {
    # Match Windows import libraries to DLLs by stem; reject ambiguous matches.
    $entry = GetEntry $Record $Name 'Dynamic'
    $stem = [IO.Path]::GetFileNameWithoutExtension($entry.linkFile)
    $files = @($Record.Metadata.runtimeFiles | Where-Object { [IO.Path]::GetFileNameWithoutExtension($_) -ceq $stem })
    if ($files.Count -ne 1) { throw "Runtime file missing or ambiguous: $Name" }
    return $files[0]
}

function WriteGenerated([string]$Path, [string]$Content) {
    # Write staging artifacts as UTF-8 without BOM or final CR/LF.
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    [IO.File]::WriteAllText($Path, $Content.TrimEnd([char[]]"`r`n"), [Text.UTF8Encoding]::new($false))
}
function RunCMake([string[]]$Arguments) {
    & $CMake @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'CMake packaging build failed.' }
}

# 4. Build MD/MT in separate prefixes; install Debug/Release together for each CRT.
$records = @()
foreach ($runtime in @('Dynamic', 'Static')) {
    $build = Join-Path $output "build-$runtime"
    $install = Join-Path $output "install-$runtime"
    RunCMake @('-S', $repository, '-B', $build, '-G', $Generator, '-A', 'x64', "-DUniversalDevKitRuntime=$runtime", "-DCMAKE_INSTALL_PREFIX=$install", ('-DUniversalDevKit_COMPONENTS=' + ($selected -join ';')))
    foreach ($configuration in @('Debug', 'Release')) {
        RunCMake @('--build', $build, '--config', $configuration)
        RunCMake @('--install', $build, '--config', $configuration)
        $metadata = if ($hasBinaries) {
            Get-Content (Join-Path $install "lib/cmake/UniversalDevKit/UniversalDevKit.Build-$configuration.json") -Raw | ConvertFrom-Json
        } else {
            # Header-only releases have no binary manifest or CRT/ABI restrictions.
            [pscustomobject]@{ schemaVersion = 1; platform = 'Windows'; architecture = 'x64'; compilerId = 'MSVC'; runtime = $runtime; version = $version; toolset = ''; compilerVersion = ''; components = @(); runtimeFiles = @() }
        }
        if ($metadata.schemaVersion -ne 1 -or $metadata.platform -ne 'Windows' -or $metadata.architecture -ne 'x64' -or
            $metadata.compilerId -ne 'MSVC' -or $metadata.runtime -ne $runtime -or $metadata.version -ne $version) { throw 'Unexpected binary release metadata.' }
        $records += [pscustomobject]@{ Runtime = $runtime; Configuration = $configuration; Install = $install; Metadata = $metadata }
    }
}

# 5. Verify compiler/toolset consistency; tools and cl.exe versions may differ.
$toolset = $records[0].Metadata.toolset
$compiler = $records[0].Metadata.compilerVersion
$cache = Get-Content (Join-Path $output 'build-Dynamic/CMakeCache.txt') -Raw
$vcTools = [regex]::Match($cache, '/MSVC/([^/]+)/bin/').Groups[1].Value
if ($hasBinaries -and -not $vcTools) { throw 'Cannot determine actual VCToolsVersion.' }
foreach ($record in $records) {
    if ($record.Metadata.toolset -ne $toolset -or $record.Metadata.compilerVersion -ne $compiler) { throw 'Cannot combine compilers in one NuGet release.' }
}

# 6. Create one component package; dependency binaries remain in their own packages.
foreach ($component in $selected) {
    $package = $packages[$component]
    # Use fresh staging to avoid carrying stale files into a new release.
    $stage = Join-Path $output ('staging/' + $component + '-' + [Guid]::NewGuid().ToString('N'))
    $payload = Join-Path $stage 'payload'
    [void][IO.Directory]::CreateDirectory((Join-Path $payload 'include'))
    Copy-Item -LiteralPath $license -Destination (Join-Path $payload 'LICENSE.txt')
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'README.md') -Destination (Join-Path $payload 'README.md')

    # Preserve public include paths for common and component headers.
    foreach ($headerRoot in @('Includes/Core', "Includes/$component")) {
        $sourceRoot = Join-Path $repository $headerRoot
        foreach ($header in Get-ChildItem -LiteralPath $sourceRoot -File -Recurse) {
            $relative = $header.FullName.Substring($sourceRoot.Length + 1)
            $headerDestination = Join-Path $payload "include/$relative"
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($headerDestination))
            Copy-Item -LiteralPath $header.FullName -Destination $headerDestination -Force
        }
    }
    $variants = [Collections.Generic.List[string]]::new()
    $componentGraphs = @($graphs.Keys | Where-Object { $_.StartsWith($component + '.', [StringComparison]::Ordinal) } | Sort-Object)
    foreach ($record in $records) {
        $runtime = $record.Runtime
        $configuration = $record.Configuration
        $destination = Join-Path $payload "binaries/$runtime/$configuration"
        [void][IO.Directory]::CreateDirectory($destination)
        if ($hasBinaries) { Copy-Item -LiteralPath (Join-Path $record.Install "lib/cmake/UniversalDevKit/UniversalDevKit.Build-$configuration.json") -Destination (Join-Path $destination 'Release.json') }

        # Copy only this component's libraries and DLLs for the current configuration.
        foreach ($entry in @($record.Metadata.components | Where-Object { $_.name -ceq $component })) {
            Copy-Item -LiteralPath (Join-Path $record.Install $entry.linkFile) -Destination $destination
            if ($entry.variant -eq 'Dynamic') { Copy-Item -LiteralPath (Join-Path $record.Install (GetDll $record $component)) -Destination $destination }
        }

        # Generate consumer settings for each mode and CRT/configuration.
        foreach ($key in $componentGraphs) {
            $mode = $key.Substring($component.Length + 1)
            $graph = $graphs[$key]
            $condition = (RootCondition $component $mode) + " and '`$(UniversalDevKitRuntime)' == '$runtime' and '`$(Configuration)' == '$configuration'"
            $root = '$(__UniversalDevKit' + $component + 'PackageRoot)'
            $guard = "binaries\$runtime\$configuration\Abi.h"
            if ($hasBinaries) {
                # Forced includes validate the actual settings of each compilation unit.
                Copy-Item -LiteralPath (Join-Path $record.Install "lib/cmake/UniversalDevKit/UniversalDevKit.Abi-$configuration.h") -Destination (Join-Path $destination 'Abi.h')
                $compilerParts = $compiler -split '\.'
                $fullCompiler = $compilerParts[0] + $compilerParts[1] + $compilerParts[2]
                $abiText = Get-Content (Join-Path $destination 'Abi.h') -Raw
                WriteGenerated (Join-Path $destination 'Abi.h') ($abiText.TrimEnd() + "`n#if _MSC_FULL_VER != $fullCompiler`n#error UniversalDevKit package exact compiler mismatch`n#endif")
            }
            $definitions = (@($graph.DefinitionComponents | ForEach-Object { 'UNIVERSALDEVKIT_' + $_.ToUpperInvariant() + '_DYNAMIC' }) -join ';') + ';'
            $includes = (@($graph.RequirementComponents | ForEach-Object { (PackageRoot $_) + 'include' }) -join ';') + ';'
            $link = ''

            # Expose static dependency closure to the linker; private static code inside DLLs stays internal.
            foreach ($name in $graph.LinkComponents) {
                if ($registry[$name].Kind -eq 'headerOnly') { continue }
                $entry = GetEntry $record $name $graph.ResolvedModes[$name]
                $link += (PackageRoot $name) + "binaries\$runtime\$configuration\" + (Split-Path $entry.linkFile -Leaf) + ';'
            }

            # Add required system libraries for static implementations.
            foreach ($name in $graph.SystemLibraryComponents) {
                foreach ($library in $registry[$name].Requirements.Libraries['Windows']) {
                    $link += $library + $(if ($library.EndsWith('.lib')) { ';' } else { '.lib;' })
                }
            }
            $forced = if ($hasBinaries) { "$root$guard;" } else { '' }
            $variants.Add("  <ItemDefinitionGroup Condition=`"$condition`"><ClCompile><AdditionalIncludeDirectories>$includes%(AdditionalIncludeDirectories)</AdditionalIncludeDirectories><ForcedIncludeFiles>$forced%(ForcedIncludeFiles)</ForcedIncludeFiles><PreprocessorDefinitions>$definitions%(PreprocessorDefinitions)</PreprocessorDefinitions></ClCompile><Link><AdditionalDependencies>$link%(AdditionalDependencies)</AdditionalDependencies></Link></ItemDefinitionGroup>")

            # Include private transitive DLLs in the runtime set.
            foreach ($name in $graph.RuntimeComponents) {
                $dllName = Split-Path (GetDll $record $name) -Leaf
                $path = (PackageRoot $name) + "binaries\$runtime\$configuration\$dllName"
                $variants.Add("  <ItemGroup Condition=`"$condition`"><__UniversalDevKit${component}NuGetRuntime Include=`"$path`" /></ItemGroup>")
            }
        }
    }

    # 7. Generate restore/version checks and conflicts between selected root graphs.
    $checks = [Collections.Generic.List[string]]::new()
    foreach ($key in $componentGraphs) {
        $mode = $key.Substring($component.Length + 1)
        $graph = $graphs[$key]
        $condition = RootCondition $component $mode

        # Require imports and exact release versions for all dependency packages.
        foreach ($name in $graph.ResolvedComponents) {
            $checks.Add('    <Error Condition="' + $condition + ' and ''$(__UniversalDevKit' + $name + 'PackageVersion)'' != ''{{VERSION}}''" Text="Restore/import UniversalDevKit.' + $name + ' of the exact release version." />')
        }

        # Independent roots may require conflicting variants of a transitive component.
        foreach ($otherKey in @($graphs.Keys | Sort-Object)) {
            $separator = $otherKey.LastIndexOf('.')
            $other = $otherKey.Substring(0, $separator)
            if ($other -eq $component) { continue }
            $otherMode = $otherKey.Substring($separator + 1)
            $otherGraph = $graphs[$otherKey]
            foreach ($name in $graph.ResolvedComponents) {
                if ($otherGraph.ResolvedModes.ContainsKey($name) -and $otherGraph.ResolvedModes[$name] -ne $graph.ResolvedModes[$name]) {
                    $both = $condition + ' and ' + (RootCondition $other $otherMode)
                    $checks.Add('    <Error Condition="' + $both + '" Text="Conflicting NuGet linkage for ' + $name + ': ' + $key + ' versus ' + $otherKey + '." />')
                }
            }
        }
    }

    # 8. Generate calculated settings; package-owned props/targets define integration behavior.
    $dependencies = (@($registry[$component].Dependencies | ForEach-Object { '<dependency id="' + $packages[$_.Component].Id + '" version="[' + $version + ']" />' }) -join '')
    $validModes = (@($componentGraphs | ForEach-Object { $_.Substring($component.Length + 1) }) -join ';')
    $unknown = (@($selected | ForEach-Object { "'%(__UniversalDevKitNuGetRoot.Identity)' != '$_'" }) -join ' and ')
    $settings = [Collections.Generic.List[string]]::new()
    $settings.Add('<?xml version="1.0" encoding="utf-8"?>')
    $settings.Add('<!-- Generated by Build.ps1. Edit the registry and build settings. -->')
    $settings.Add('<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003"><PropertyGroup>')
    foreach ($pair in @(
        @{ Key = 'PackageVersion'; Value = $version },
        @{ Key = 'ValidModes'; Value = $validModes },
        @{ Key = 'HasBinaries'; Value = $hasBinaries.ToString().ToLowerInvariant() },
        @{ Key = 'ExpectedToolset'; Value = $toolset },
        @{ Key = 'ExpectedTools'; Value = $vcTools }
    )) {
        $key = '__UniversalDevKit' + $component + $pair.Key
        $settings.Add("  <$key>$($pair.Value)</$key>")
    }
    $settings.Add('</PropertyGroup></Project>')
    WriteGenerated (Join-Path $payload 'build/native/Generated/Settings.props') ($settings -join "`n")
    $target = @(
        '<?xml version="1.0" encoding="utf-8"?>',
        '<!-- Generated by Build.ps1. Edit the registry and build settings. -->',
        '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">',
        ($variants -join "`n"),
        '  <ItemGroup><__UniversalDevKitNuGetRoot Include="$(UniversalDevKitComponents)" /></ItemGroup>',
        ('  <Target Name="__UniversalDevKit' + $component + 'ValidatePackageGraph" BeforeTargets="PrepareForBuild">'),
        ('    <Error Condition="' + $unknown + '" Text="Unknown packaged component: %(__UniversalDevKitNuGetRoot.Identity)." />'),
        (($checks -join "`n").Replace('{{VERSION}}', $version)),
        '  </Target>',
        '</Project>'
    ) -join "`n"
    WriteGenerated (Join-Path $payload 'build/native/Generated/Settings.targets') $target
    # Preserve relative paths of auxiliary integration imports and resources.
    $integrationDirectory = Split-Path -Parent $package.Integration['targets']
    foreach ($file in Get-ChildItem -LiteralPath $integrationDirectory -File -Recurse) {
        $relative = $file.FullName.Substring($integrationDirectory.Length + 1)
        if ($file.Extension -notin @('.props', '.targets') -and $relative -notmatch '[\\/]') { continue }
        if ($relative -match '^Generated[\\/]') { throw 'Generated is reserved for calculated package settings.' }
        $destination = Join-Path $payload "build/native/$relative"
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
        Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
    }
    # Copy package integration files verbatim.
    foreach ($kind in $package.Integration.Keys) {
        Copy-Item -LiteralPath $package.Integration[$kind] -Destination (Join-Path $payload "build/native/$($package.Id).$kind") -Force
    }
    $spec = Get-Content -LiteralPath $package.Nuspec -Raw
    WriteGenerated (Join-Path $stage "$component.nuspec") ($spec.Replace('{{COMPONENT}}', $component).Replace('{{PACKAGE_ID}}', $package.Id).Replace('{{VERSION}}', $version).Replace('{{DEPENDENCIES}}', $dependencies))

    # 9. Create local nupkg files without publishing them.
    # Native DLLs use targets; managed lib/ref analysis does not apply.
    & $NuGet pack (Join-Path $stage "$component.nuspec") -BasePath $stage -OutputDirectory $output -NonInteractive -ForceEnglishOutput -Properties 'NoWarn=NU5100;NU5128' | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "NuGet pack failed for $component" }
}
Write-Host "NuGet feed: $output"