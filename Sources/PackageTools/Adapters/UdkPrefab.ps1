function Invoke-UdkPrefabProject($Project, $Context) {
    $repository = $Context.RepositoryPath
    $version = $Context.Version
    $Components = @($Project.component)
    $Configuration = if ($Context.Options.Configuration) {
        $Context.Options.Configuration
    } else {
        $Project.configuration
    }
    $Abi = if ($Context.Options.Abi) {
        $Context.Options.Abi
    } else {
        $Project.abis
    }
    $ApiLevel = if ($Context.Options.ApiLevel) {
        $Context.Options.ApiLevel
    } else {
        $Project.apiLevel
    }
    $CMake = Resolve-UdkCMake $Context.CMake
    $Ninja = Resolve-UdkNinja $Context.Options.Ninja $CMake
    . (Join-Path $repository $Project.toolchain)
    $AndroidNdk = (Resolve-UdkAndroidToolchain -AndroidNdk $Context.Options.AndroidNdk).AndroidNdk
    $revision = ((Get-Content (Join-Path $AndroidNdk 'source.properties') | Where-Object {
        $_ -match '^Pkg.Revision\s*='
        }) -split '=')[1].Trim()
    $ndkMajor = [int]$revision.Split('.')[0]
    $connection = Join-Path $repository 'Scripts/PowerShell/Modules/Module.Udk.Connection/Private'
    . (Join-Path $connection 'Requirements.ps1')
    . (Join-Path $connection 'ComponentRegistry.ps1')
    . (Join-Path $connection 'ConnectionPlan.ps1')
    $registry = Get-UdkComponentRegistry $repository
    $deliveries = @{
        $Project.component = $Context.Delivery
    }
    $physicalOutput = $Context.WorkDirectory
    $artifactDrive = New-UdkArtifactDrive -Path $physicalOutput
    try {
        $output = $artifactDrive.Path
        $work = Join-Path $output 'build'
        # Save metadata without a newline at the end.
        function WriteText([string]$Path, [string]$Text) {
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
            [IO.File]::WriteAllText($Path, $Text.TrimEnd([char[]]"`r`n"), [Text.UTF8Encoding]::new($false))
        }

        function WriteJson([string]$Path, $Value) {
            WriteText $Path ($Value | ConvertTo-Json -Depth 30)
        }

        # Stop if CMake fails so the package does not contain missing files.
        function RunCMake([string[]]$Arguments) {
            & $CMake @Arguments | Out-Host
            if ($LASTEXITCODE -ne 0) {
                throw 'Android CMake build failed.'
            }
        }

        # Build and install the shared source code for each ABI.
        # Read library names from the install metadata instead of guessing their paths.
        $records = @{}
        $compiledComponents = @($Components | Where-Object {
            $registry[$_].Kind -ne 'headerOnly'
        })
        foreach ($architecture in $(if ($compiledComponents.Count) {
            $Abi
                } else {
                    @()
        })) {
            $build = Join-Path $work $architecture
            $prefix = Join-Path $build 'install'

            # Set the compiler mode because Windows short paths can remove ++ from clang++.
            RunCMake @(
                '-S',
                $repository,
                '-B',
                $build,
                '-G',
                'Ninja',
                "-DCMAKE_MAKE_PROGRAM=$Ninja",
                "-DCMAKE_TOOLCHAIN_FILE=$AndroidNdk/build/cmake/android.toolchain.cmake",
                '-DCMAKE_CXX_COMPILER_ARG1=--driver-mode=g++',
                '-DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON',
                "-DANDROID_ABI=$architecture",
                "-DANDROID_PLATFORM=android-$ApiLevel",
                '-DANDROID_STL=c++_shared',
                "-DCMAKE_BUILD_TYPE=$Configuration",
                "-DCMAKE_INSTALL_PREFIX=$prefix",
                "-DUniversalDevKit_COMPONENTS=$($compiledComponents -join ';')"
            )
            RunCMake @('--build', $build, '--parallel', '4')
            RunCMake @('--install', $build)
            $metadata = Get-Content (Join-Path $prefix "lib/cmake/UniversalDevKit/UniversalDevKit.Build-$Configuration.json") -Raw | ConvertFrom-Json
            if ($metadata.platform -ne 'Android') {
                throw 'Expected Android build metadata.'
            }
            $records[$architecture] = @{
                Prefix = $prefix
                Metadata = $metadata
            }
        }

        # Load ZIP support for AAR files.
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        Add-Type -AssemblyName System.IO.Compression

        function ModuleName([string]$Component, [string]$Mode) {
            return ($Component + '_' + $Mode).ToLowerInvariant()
        }


        # Prepare files for each root component and supported variant.
        # Components with process-wide state use Dynamic only. Keep private dependency headers out of public includes.
        foreach ($component in $Components) {
            if (-not $registry.ContainsKey($component)) {
                throw "Unknown component: $component"
            }
            $modes = if ($registry[$component].Kind -eq 'headerOnly') {
                @('Shared')
            } elseif ($registry[$component].StateScope -eq 'process') {
                @('Dynamic')
            } else {
                @('Static', 'Dynamic')
            }
            foreach ($mode in $modes) {
                # Resolve dependencies and create a clean staging directory for this result.
                $graph = Resolve-UdkLinkageGraph @($component) @{
                    $component = $mode
                } $registry
                $packageName = 'udk_' + (ModuleName $component $mode)
                $delivery = $deliveries[$component]
                $artifact = $delivery.artifactPrefix + '-' + $mode.ToLowerInvariant() + '-' + $Configuration.ToLowerInvariant()
                $stage = Reset-UdkArtifactDirectory -Root $output -Path (Join-Path $output "payload/$mode")

                # Write Android and Prefab manifests. Copy only public headers.
                WriteText (Join-Path $stage 'AndroidManifest.xml') ('<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="org.universaldevkit.' + $packageName + '"><uses-sdk android:minSdkVersion="' + $ApiLevel + '"/></manifest>')
                WriteJson (Join-Path $stage 'prefab/prefab.json') @{
                    schema_version = 2
                    name = $packageName
                    version = $version
                    dependencies = @()
                }
                $linkSet = @(@($graph.LinkComponents) + @($graph.RuntimeComponents) | Where-Object {
                    $registry[$_].Kind -ne 'headerOnly'
                    } | Sort-Object -Unique)
                $rootModule = Join-Path $stage "prefab/modules/$component"
                $include = Join-Path $rootModule 'include'
                [void][IO.Directory]::CreateDirectory($include)
                Copy-Item (Join-Path $repository 'Includes/Core/*') $include -Recurse
                foreach ($requirement in $graph.RequirementComponents) {
                    Copy-Item (Join-Path $repository "Includes/$requirement/*") $include -Recurse -Force
                    if ($graph.ResolvedModes[$requirement] -eq 'Dynamic') {
                        $export = Join-Path $include "UniversalDevKit/$requirement/Export.h"
                        $macro = 'UNIVERSALDEVKIT_' + $requirement.ToUpperInvariant() + '_DYNAMIC'
                        WriteText $export ("// Generated by UdkPrefab.ps1. Source: component export header.`n#pragma once`n#ifndef $macro`n#define $macro`n#endif`n" + [IO.File]::ReadAllText($export))
                    }
                }

                # Save the settings that the consumer checks before linking.
                $standard = ($graph.RequirementComponents | ForEach-Object {
                    $registry[$_].Requirements.CxxStandard
                    } | Measure-Object -Maximum).Maximum
                $contract = @{
                    schemaVersion = 1
                    version = $version
                    ndk = $revision
                    stl = 'c++_shared'
                    api = $ApiLevel
                    configuration = $Configuration
                    modes = $graph.ResolvedModes
                    package = $packageName
                    component = $component
                    cxxStandard = [int]$standard
                    pageSize = 16384
                }
                WriteJson (Join-Path $include 'UniversalDevKit/Android/contract.json') $contract
                Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../Templates/PrefabConsumer.cmake') -Destination (Join-Path $include 'UniversalDevKit/Android/Consumer.cmake')

                # A header-only Prefab module has no libraries or placeholder binaries.
                WriteJson (Join-Path $rootModule 'module.json') @{
                    export_libraries = @()
                }

                # Describe Prefab modules and copy binaries for all selected ABIs.
                # Internal modules provide libraries at link time and runtime, without their own include paths.
                foreach ($name in $linkSet) {
                    $resolvedMode = $graph.ResolvedModes[$name]
                    $moduleName = if ($name -eq $component) {
                        $component
                    } else {
                        'internal_' + (ModuleName $name $resolvedMode)
                    }
                    $module = Join-Path $stage "prefab/modules/$moduleName"
                    $exports = @()

                    # Use the build dependency graph for Prefab links and system libraries.
                    foreach ($dependency in $registry[$name].Dependencies) {
                        if ($dependency.Component -in $linkSet) {
                            $exports += ':internal_' + (ModuleName $dependency.Component $graph.ResolvedModes[$dependency.Component])
                        }
                    }
                    $systemSources = if ($name -eq $component) {
                        @($graph.SystemLibraryComponents)

                    } elseif ($resolvedMode -eq 'Static') {
                        @($name)
                    } else {
                        @()
                    }
                    foreach ($systemSource in $systemSources) {
                        foreach ($library in @($registry[$systemSource].Requirements.Libraries.Android)) {
                            if ($library) {
                                $exports += '-l' + $library
                            }
                        }
                    }

                    WriteJson (Join-Path $module 'module.json') @{
                        export_libraries = @($exports)
                    }
                    foreach ($architecture in $Abi) {
                        $record = $records[$architecture]
                        $entries = @($record.Metadata.components | Where-Object {
                            $_.name -ceq $name -and $_.variant -ceq $resolvedMode
                        })
                        if ($entries.Count -ne 1) {
                            throw "Missing Android artifact: $name.$resolvedMode"
                        }
                        $source = Join-Path $record.Prefix $entries[0].linkFile

                        # Prefab selects files by module name. Keep the shared library SONAME unchanged.
                        $stem = [IO.Path]::GetFileNameWithoutExtension($source)
                        WriteJson (Join-Path $module 'module.json') @{
                            library_name = $stem
                            export_libraries = @($exports)
                        }
                        $libs = Join-Path $module "libs/android.$architecture"
                        [void][IO.Directory]::CreateDirectory($libs)
                        Copy-Item -LiteralPath $source -Destination $libs
                        WriteJson (Join-Path $libs 'abi.json') @{
                            abi = $architecture
                            api = $ApiLevel
                            ndk = $ndkMajor
                            stl = 'c++_shared'
                            static = ($resolvedMode -eq 'Static')
                        }
                    }
                }

                # Add the license and release metadata to the prepared files.
                Copy-Item -LiteralPath (Join-Path $repository 'LICENSE') -Destination (Join-Path $stage 'LICENSE.txt')
                if ($graph.ResolvedModes.ContainsKey('Diagnostic')) {
                    [void][IO.Directory]::CreateDirectory((Join-Path $stage 'licenses'))
                    Copy-Item -LiteralPath (Join-Path $repository 'ThirdParty/spdlog/LICENSE') -Destination (Join-Path $stage 'licenses/spdlog.LICENSE')
                }
                if ($component -eq 'OpenGLESRenderer') {
                    [void][IO.Directory]::CreateDirectory((Join-Path $stage 'licenses'))
                    foreach ($name in @('stb_truetype.h', 'nanosvg.h', 'nanosvgrast.h')) {
                        Copy-Item -LiteralPath (Join-Path $repository "ThirdParty/XamlRuntime/$name") -Destination (Join-Path $stage 'licenses')
                    }
                }
                WriteJson (Join-Path $stage 'udk-release.json') $contract


            }
        }
        return @{
            output = Join-Path $physicalOutput 'payload'
        }
    } finally {
        Remove-UdkArtifactDrive $artifactDrive
    }
}