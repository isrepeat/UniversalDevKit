function Invoke-UdkNativeProject($Project, $Context) {
    $repository = $Context.RepositoryPath
    $version = $Context.Version
    $Generator = $Project.generator
    $CMake = Resolve-UdkCMake $Context.CMake
    $output = Resolve-UdkBuildPath $repository $repository $Project.buildDirectory
    [void][IO.Directory]::CreateDirectory($output)
    $physicalOutput = $output
    $artifactDrive = New-UdkArtifactDrive -Path $output
    try {
    $output = $artifactDrive.Path
    $connection = Join-Path $repository 'Scripts/PowerShell/Modules/Module.Udk.Connection/Private'
    . (Join-Path $connection 'Requirements.ps1')
    . (Join-Path $connection 'ComponentRegistry.ps1')
    . (Join-Path $connection 'ConnectionPlan.ps1')
    $registry = Get-UdkComponentRegistry $repository
    $selected = @(Resolve-UdkComponents @($Project.component) $registry)
    $hasBinaries = @($selected | Where-Object { $registry[$_].Kind -ne 'headerOnly' }).Count -gt 0
    $packages = @{}
    foreach ($file in Get-ChildItem (Join-Path $repository 'Packages') -Filter Package.json -Recurse -File) {
        $definition = Read-UdkBuildJson $file.FullName
        if ($definition.schemaVersion -ne 2 -or -not $definition.deliveries.NuGet) { continue }
        $native = @($definition.projects.PSObject.Properties.Value | Where-Object { $_.adapter -eq 'udk-native' })
        if (-not $native.Count) { continue }
        if ($native.Count -ne 1) { throw 'A native package requires one native project.' }
        $name = $native[0].component
        if (-not $registry.ContainsKey($name)) { continue }
        $directory = Split-Path -Parent (Join-Path $file.DirectoryName $definition.deliveries.NuGet)
        $delivery = Read-UdkBuildJson (Join-Path $file.DirectoryName $definition.deliveries.NuGet)
        $integration = @{}
        foreach ($kind in @('props','targets')) { if ($delivery.integration.$kind) { $integration[$kind] = Resolve-UdkBuildPath $file.DirectoryName $directory $delivery.integration.$kind -Existing } }
        if (-not $integration.targets) { throw "Missing native integration targets: $name" }
        $runtimes = if ($delivery.supportedRuntimes) { @($delivery.supportedRuntimes) } else { @('Dynamic','Static') }
        if (@($runtimes | Where-Object { $_ -notin @('Dynamic','Static') }).Count) { throw 'Invalid supportedRuntimes.' }
        $prepare = if ($delivery.preparationScript) { Resolve-UdkBuildPath $file.DirectoryName $directory $delivery.preparationScript -Existing } else { $null }
        $stageScript = if ($delivery.stagingScript) { Resolve-UdkBuildPath $file.DirectoryName $directory $delivery.stagingScript -Existing } else { $null }
        if ($packages.ContainsKey($name)) { throw "Duplicate native package: $name" }
        $packages[$name] = [pscustomobject]@{ Id=$delivery.id; Integration=$integration; SupportedRuntimes=$runtimes; PreparationScript=$prepare; StagingScript=$stageScript; DependencyName=$(if ($delivery.dependencyName) { $delivery.dependencyName } else { $name }) }
    }
    foreach ($name in $selected) { if (-not $packages.ContainsKey($name)) { throw "Missing native package: $name" } }
    $graphs = @{}
    foreach ($name in ($packages.Keys | Sort-Object)) {
        $modes = if ($registry[$name].Kind -eq 'headerOnly') { @('Shared') } elseif ($registry[$name].StateScope -eq 'process') { @('Dynamic') } else { @('Static','Dynamic') }
        foreach ($mode in $modes) { $graphs["$name.$mode"] = Resolve-UdkLinkageGraph @($name) @{ $name=$mode } $registry }
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
$preparations = @{}
foreach ($runtime in @('Dynamic', 'Static')) {
    $runtimeComponents = @($selected | Where-Object { $runtime -in $packages[$_].SupportedRuntimes })
    if (-not $runtimeComponents.Count) { continue }
    # Подготовка зависимостей завершается до configure; рабочие каталоги сохраняются между выпусками.
    $dependencyDefinitions = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
    foreach ($component in $selected) {
        $package = $packages[$component]
        if (-not $package.PreparationScript -or $runtime -notin $package.SupportedRuntimes) { continue }
        $workDirectory = Join-Path $output "dependencies/$($package.DependencyName)/$runtime"
        [void][IO.Directory]::CreateDirectory($workDirectory)
        $prepared = @(& $package.PreparationScript -RepositoryPath $repository -WorkDirectory $workDirectory -Runtime $runtime -Configurations @('Debug', 'Release') -Generator $Generator)
        if ($prepared.Count -ne 1 -or $prepared[0] -isnot [Collections.IDictionary]) {
            throw "Preparation script must return one dictionary of CMake definitions: $component"
        }
        $preparations["$component/$runtime"] = $prepared[0]
        foreach ($key in $prepared[0].Keys) {
            if ($key -isnot [string] -or $key -cnotmatch '^UniversalDevKit[A-Za-z0-9_]+$' -or
                $key -in @('UniversalDevKitRuntime', 'UniversalDevKit_COMPONENTS', 'UniversalDevKit_ENFORCE_RELEASE_POLICY') -or
                $prepared[0][$key] -isnot [string]) {
                throw "Invalid preparation CMake definition from ${component}: $key"
            }
            if ($dependencyDefinitions.ContainsKey($key) -and $dependencyDefinitions[$key] -cne $prepared[0][$key]) {
                throw "Conflicting preparation CMake definition: $key"
            }
            $dependencyDefinitions[$key] = $prepared[0][$key]
        }
    }
    $dependencyArguments = @($dependencyDefinitions.Keys | Sort-Object -CaseSensitive | ForEach-Object { '-D' + $_ + '=' + $dependencyDefinitions[$_] })
    if ($dependencyDefinitions.ContainsKey('UniversalDevKitAngleRoot')) {
        # Обновляем результаты find при переносе установки ANGLE.
        $dependencyArguments += '-UudkAngle*'
    }
    $build = Join-Path $output "build/$runtime"
    $install = Reset-UdkArtifactDirectory -Root $output -Path (Join-Path $output "install/$runtime")
    RunCMake (@('-S', $repository, '-B', $build, '-G', $Generator, '-A', 'x64', '-DCMAKE_CONFIGURATION_TYPES=Debug;Release', '-DUniversalDevKit_ENFORCE_RELEASE_POLICY=ON', "-DUniversalDevKitRuntime=$runtime", "-DCMAKE_INSTALL_PREFIX=$install", ('-DUniversalDevKit_COMPONENTS=' + ($runtimeComponents -join ';'))) + $dependencyArguments)
    foreach ($configuration in @('Debug', 'Release')) {
        RunCMake @('--build', $build, '--config', $configuration, '--parallel', '4')
        RunCMake @('--install', $build, '--config', $configuration)
        $metadata = if (@($runtimeComponents | Where-Object { $registry[$_].Kind -ne 'headerOnly' }).Count -gt 0) {
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
$cache = Get-Content (Join-Path $output 'build/Dynamic/CMakeCache.txt') -Raw
$vcTools = [regex]::Match($cache, '/MSVC/([^/]+)/bin/').Groups[1].Value
if ($hasBinaries -and -not $vcTools) { throw 'Cannot determine actual VCToolsVersion.' }
foreach ($record in $records) {
    if (-not @($record.Metadata.components).Count) { continue }
    if ($record.Metadata.toolset -ne $toolset -or $record.Metadata.compilerVersion -ne $compiler) { throw 'Cannot combine compilers in one NuGet release.' }
}


# 6. Create one component package; dependency binaries remain in their own packages.
foreach ($component in @($Project.component)) {
    $componentHasBinaries = $registry[$component].Kind -ne 'headerOnly'
    $package = $packages[$component]
    # Use fresh staging to avoid carrying stale files into a new release.
    $stage = Reset-UdkArtifactDirectory -Root $output -Path (Join-Path $output "staging/$component")
    $payload = Join-Path $stage 'payload'
    [void][IO.Directory]::CreateDirectory((Join-Path $payload 'include'))

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
        if ($runtime -notin $package.SupportedRuntimes) { continue }
        $configuration = $record.Configuration
        $destination = Join-Path $payload "binaries/$runtime/$configuration"
        [void][IO.Directory]::CreateDirectory($destination)
        if ($componentHasBinaries) { Copy-Item -LiteralPath (Join-Path $record.Install "lib/cmake/UniversalDevKit/UniversalDevKit.Build-$configuration.json") -Destination (Join-Path $destination 'Release.json') }

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
            if ($componentHasBinaries) {
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
            $forced = if ($componentHasBinaries) { "$root$guard;" } else { '' }
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
    $validModes = (@($componentGraphs | ForEach-Object { $_.Substring($component.Length + 1) }) -join ';')
    $unknown = (@($packages.Keys | Sort-Object | ForEach-Object { "'%(__UniversalDevKitNuGetRoot.Identity)' != '$_'" }) -join ' and ')
    $settings = [Collections.Generic.List[string]]::new()
    $settings.Add('<?xml version="1.0" encoding="utf-8"?>')
    $settings.Add('<!-- Generated by Build.ps1. Edit the registry and build settings. -->')
    $settings.Add('<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003"><PropertyGroup>')
    foreach ($pair in @(
        @{ Key = 'PackageVersion'; Value = $version },
        @{ Key = 'ValidModes'; Value = $validModes },
        @{ Key = 'HasBinaries'; Value = $componentHasBinaries.ToString().ToLowerInvariant() },
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
    # PackageReference передаёт интеграцию зависимостей через buildTransitive.
    # Обёртки используют те же файлы, что и packages.config, без копии реализации.
    foreach ($kind in $package.Integration.Keys) {
        $wrapper = '<?xml version="1.0" encoding="utf-8"?>' + "`n" +
            '<!-- Generated by Build.ps1. Source: package integration. -->' + "`n" +
            '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + "`n" +
            '  <Import Project="$(MSBuildThisFileDirectory)..\..\build\native\' + $package.Id + '.' + $kind + '" />' + "`n" + '</Project>'
        WriteGenerated (Join-Path $payload "buildTransitive/native/$($package.Id).$kind") $wrapper
    }
    if ($package.StagingScript) {
        $componentPreparations = @{}
        foreach ($runtime in $package.SupportedRuntimes) {
            if ($preparations.ContainsKey("$component/$runtime")) { $componentPreparations[$runtime] = $preparations["$component/$runtime"] }
        }
        & $package.StagingScript -Payload $payload -RepositoryPath $repository -Preparations $componentPreparations
    }

    }
    $deps = @(foreach ($dependency in $registry[$Project.component].Dependencies) { [pscustomobject]@{ id=$packages[$dependency.Component].Id; version=$version } })
    $Context.Delivery | Add-Member -NotePropertyName dependencies -NotePropertyValue $deps -Force
    return @{ output = Join-Path $physicalOutput "staging/$($Project.component)/payload" }
    } finally { Remove-UdkArtifactDrive $artifactDrive }
}