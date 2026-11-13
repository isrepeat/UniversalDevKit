param(
    [Parameter(Mandatory)][string]$PackagePath,
    [string]$RepositoryPath,
    [string]$OutputDirectory,
    [string]$CMake,
    [string]$NuGet = 'nuget.exe',
    [string]$PackageSources,
    [hashtable]$Properties = @{},
    [switch]$Plan,
    [string]$Delivery,
    [string]$AndroidNdk,
    [string]$AndroidSdk,
    [string]$JavaHome,
    [string]$Gradle,
    [string]$Ninja,
    [ValidateSet('Debug','Release')][string]$Configuration,
    [ValidateSet('arm64-v8a','x86_64')][string[]]$Abi,
    [ValidateRange(24,35)][Nullable[int]]$ApiLevel,
    [hashtable]$ReleaseState = @{}
)

$ErrorActionPreference = 'Stop'
$env:DOTNET_CLI_UI_LANGUAGE = 'en-US'
$env:VSLANG = '1033'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)
if (-not $RepositoryPath) {
    $RepositoryPath = (Get-Location).Path
}
. (Join-Path $PSScriptRoot 'Private/Contract.ps1')
. (Join-Path $PSScriptRoot 'Private/ArtifactDirectories.ps1')
. (Join-Path $PSScriptRoot 'Private/Tools.ps1')
foreach ($adapter in @('DotNet', 'ComponentSources', 'CMakeInstall', 'Files', 'NuGetRestore', 'NuGet', 'UdkNative', 'UdkPrefab', 'GradlePublish', 'Maven')) {
    . (Join-Path $PSScriptRoot "Adapters/$adapter.ps1")
}

function Invoke-UdkBuildTool([string]$Tool, [string[]]$Arguments) {
    & $Tool @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "$Tool failed with exit code $LASTEXITCODE."
    }
}

$buildPlan = Get-UdkPackagePlan $RepositoryPath $PackagePath $Delivery
$projectDirectory = Join-Path $buildPlan.RepositoryPath ('!artifacts/package-build/' + $buildPlan.Package.name)
foreach ($property in $Properties.Keys) {
    $owners = @($buildPlan.Order | Where-Object {
        $property -cin $buildPlan.Projects[$_].preparation.properties
    })
    if (-not $owners.Count) {
        throw "Unknown build property: $property"
    }
}
if ($Plan) {
    return $buildPlan
}
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'This build profile requires Windows.'
}
if (-not $ReleaseState.ContainsKey('results')) {
    $ReleaseState.results = @{}
}
$releaseKey = $buildPlan.PackagePath + '|' + $buildPlan.DeliveryName
if ($ReleaseState.results.ContainsKey($releaseKey)) {
    return $ReleaseState.results[$releaseKey]
}
$isNuGet = $buildPlan.Delivery.adapter -eq 'nuget'
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $buildPlan.RepositoryPath $(if ($isNuGet) {
        '!artifacts/packages/nuget'
        } else {
            '!artifacts/packages/maven'
    })
}
$baseOutput = [IO.Path]::GetFullPath($OutputDirectory)
$output = if ($isNuGet) {
    Join-Path $baseOutput $buildPlan.Package.name
} else {
    $baseOutput
}
$dependencyArtifacts = @()
foreach ($dependency in $buildPlan.ReleaseDependencies) {
    $arguments = @{
        PackagePath=$dependency.PackagePath.Substring($buildPlan.RepositoryPath.Length+1)
        RepositoryPath=$buildPlan.RepositoryPath
        Delivery=$dependency.DeliveryName
        OutputDirectory=$baseOutput
        CMake=$CMake
        NuGet=$NuGet
        PackageSources=$PackageSources
        Properties=$Properties
        AndroidNdk=$AndroidNdk
        AndroidSdk=$AndroidSdk
        JavaHome=$JavaHome
        Gradle=$Gradle
        Ninja=$Ninja
        Configuration=$Configuration
        Abi=$Abi
        ApiLevel=$ApiLevel
        ReleaseState=$ReleaseState
    }
    foreach ($key in @('Abi','Configuration','ApiLevel')) {
        if (-not $arguments[$key]) {
            $arguments.Remove($key)
        }
    }
    $dependencyArtifacts += @(& $PSCommandPath @arguments)
}
[void][IO.Directory]::CreateDirectory($output)
$lockPath = if ($isNuGet) {
    Join-Path $output '.build.lock'
} else {
    Join-Path $output ('.' + $buildPlan.Package.name + '.build.lock')
}
$lock = [IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None')
try {
    # Build the required projects, then use their named results to create the package.
    if ($isNuGet) {
        $NuGet = & (Join-Path $PSScriptRoot 'Private/GetNuGet.ps1') -LocalPath $NuGet -CacheDirectory (Join-Path $buildPlan.RepositoryPath '!tools')
    }
    $stagePath = if ($isNuGet) {
        Join-Path $output 'staging'
    } else {
        Join-Path $output ('staging/' + $buildPlan.Package.name)
    }
    $stage = Reset-UdkArtifactDirectory -Root $output -Path $stagePath
    $payload = Join-Path $stage 'payload'
    [void][IO.Directory]::CreateDirectory($payload)
    $results = @{}
    $projectLocks = [Collections.Generic.List[IO.FileStream]]::new()
    try {
        # Keep locks until all files are copied so another build cannot delete the results.
        foreach ($name in ($buildPlan.Order | Sort-Object)) {
            $work = Join-Path $projectDirectory $name
            [void][IO.Directory]::CreateDirectory($work)
            $projectLocks.Add([IO.File]::Open((Join-Path $work '.build.lock'), 'OpenOrCreate', 'ReadWrite', 'None'))
        }
        foreach ($name in $buildPlan.Order) {
            $project = $buildPlan.Projects[$name]
            $context = @{
                RepositoryPath = $buildPlan.RepositoryPath
                WorkDirectory = Join-Path $projectDirectory $name
                Properties = $Properties
                CMake = $CMake
                NuGet = $NuGet
                PackageSources = $PackageSources
                Delivery = $buildPlan.Delivery
                Version = $buildPlan.Version
                OutputDirectory = $output
                Options = @{
                    AndroidNdk=$AndroidNdk
                    AndroidSdk=$AndroidSdk
                    JavaHome=$JavaHome
                    Gradle=$Gradle
                    Ninja=$Ninja
                    Configuration=$Configuration
                    Abi=$Abi
                    ApiLevel=$ApiLevel
                }
            }
            Write-Host "Building project $name ($($project.adapter))..."
            $roots = switch ($project.adapter) {
                'dotnet' {
                    Invoke-UdkDotNetProject $project $context
                }
                'udk-dotnet' {
                    Invoke-UdkComponentDotNetProject $project $context
                }
                { $_ -in @('component-sources', 'udk-component-sources') } {
                    Invoke-UdkComponentSourcesProject $project $context
                }
                {
                    $_ -in @('cmake-install','cmake-build')
                } {
                    Invoke-UdkCMakeInstallProject $project $context
                }
                'udk-native' {
                    Invoke-UdkNativeProject $project $context
                }
                'udk-prefab' {
                    Invoke-UdkPrefabProject $project $context
                }
                'gradle-publish' {
                    Invoke-UdkGradlePublishProject $project $context
                }
                'files' {
                    Invoke-UdkFilesProject $project $context
                }
                'nuget-restore' {
                    Invoke-UdkNuGetRestoreProject $project $context
                }
            }
            $results[$name] = $roots
        }
        $destinations = @{}
        function Copy-UdkPackageFile([string]$Source, [string]$Destination) {
            if ($destinations.ContainsKey($Destination)) {
                throw "Package content collision: $Destination"
            }
            $destinations[$Destination] = $true
            [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Destination))
            Copy-Item -LiteralPath $Source -Destination $Destination
        }
        foreach ($entry in $buildPlan.Package.contents) {
            $destination = Resolve-UdkBuildPath $payload $payload $entry.destination
            $fields = @($entry.PSObject.Properties.Name)
            $source = if ('source' -in $fields) {
                Resolve-UdkBuildPath $buildPlan.RepositoryPath $buildPlan.RepositoryPath $entry.source -Existing
            } else {
                $sourceRoot = if ('root' -in $fields) {
                    $entry.root
                } else {
                    'output'
                }
                $sourcePath = if ('path' -in $fields) {
                    $entry.path
                } else {
                    '.'
                }
                $base = $results[$entry.project][$sourceRoot]
                Resolve-UdkBuildPath $base $base $sourcePath -Existing
            }
            $isFile = Test-Path -LiteralPath $source -PathType Leaf
            if ($isFile -and ('include' -in $fields -or 'exclude' -in $fields)) {
                throw 'include/exclude require a directory source.'
            }
            $includes = if ('include' -in $fields) {
                @($entry.include)
            } else {
                @('**/*')
            }
            $includePatterns = @($includes | ForEach-Object { ConvertTo-UdkContentPattern $_ })
            $files = if ($isFile) {
                @(Get-Item -LiteralPath $source -Force)
            } elseif (-not @($includes | Where-Object { $_.Contains('*') }).Count) {
                # Exact paths avoid scanning the entire repository for LICENSE and README.
                $candidates = @{}
                foreach ($include in $includes) {
                    $candidate = Resolve-UdkBuildPath $source $source $include
                    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                        $candidates[$candidate] = Get-Item -LiteralPath $candidate -Force
                    }
                }
                @($candidates.Values | Sort-Object FullName)
            } else {
                @(Get-ChildItem -LiteralPath $source -Recurse -File -Force)
            }
            $excludePatterns = if ('exclude' -in $fields) {
                @($entry.exclude | ForEach-Object { ConvertTo-UdkContentPattern $_ })
            } else {
                @()
            }
            $renames = Get-UdkContentRenames $entry
            $usedRenames = @{}
            $preserveHierarchy = 'preserveHierarchy' -notin $fields -or $entry.preserveHierarchy
            $selectedCount = 0
            foreach ($file in $files) {
                $relative = if ($isFile) {
                    $file.Name
                } else {
                    $file.FullName.Substring($source.TrimEnd('\', '/').Length + 1).Replace('\', '/')
                }
                $included = @($includePatterns | Where-Object { $relative -imatch $_ }).Count -gt 0
                $excluded = @($excludePatterns | Where-Object { $relative -imatch $_ }).Count -gt 0
                if (-not $included -or $excluded) {
                    continue
                }
                $selectedCount++
                $fileName = $file.Name
                if ($renames.ContainsKey($relative)) {
                    $fileName = $renames[$relative]
                    $usedRenames[$relative] = $true
                }
                $targetPath = if ($preserveHierarchy) {
                    $relative.Substring(0, $relative.LastIndexOf('/') + 1) + $fileName
                } else {
                    $fileName
                }
                $target = Resolve-UdkBuildPath $payload $destination $targetPath
                Copy-UdkPackageFile $file.FullName $target
            }
            if (-not $selectedCount) {
                throw "No files selected by contents: $source"
            }
            foreach ($key in $renames.Keys) {
                if (-not $usedRenames.ContainsKey($key)) {
                    throw "Unused rename source: $key"
                }
            }
        }
    } finally {
        foreach ($projectLock in $projectLocks) {
            $projectLock.Dispose()
        }
    }
    # Package the prepared files in the selected delivery format.
    $results = @()
    if ($isNuGet) {
        foreach ($dependencyArtifact in ($dependencyArtifacts | Sort-Object -Unique)) {
            if ($dependencyArtifact -notlike '*.nupkg') {
                continue
            }
            $target = Join-Path $output (Split-Path -Leaf $dependencyArtifact)
            if ([IO.Path]::GetFullPath($dependencyArtifact) -ine [IO.Path]::GetFullPath($target)) {
                Copy-Item -LiteralPath $dependencyArtifact -Destination $target -Force
            }
            $results += $target
        }
        $results += Invoke-UdkNuGetDelivery $buildPlan $stage $output $NuGet
    } else {
        $results += @(Invoke-UdkMavenDelivery $buildPlan $stage $output)
    }
    $ReleaseState.results[$releaseKey] = @($results | Sort-Object -Unique)
    Write-Output $ReleaseState.results[$releaseKey]
} finally {
    $lock.Dispose()
}