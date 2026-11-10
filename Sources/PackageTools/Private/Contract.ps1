function Assert-UdkFields($Value, [string[]]$Allowed, [string[]]$Required, [string]$Label) {
    if ($Value -isnot [pscustomobject]) {
        throw "Expected an object: $Label"
    }
    foreach ($field in $Value.PSObject.Properties.Name) {
        if ($field -notin $Allowed) {
            throw "Unknown field '$field': $Label"
        }
    }
    foreach ($field in $Required) {
        if ($null -eq $Value.$field -or ($Value.$field -is [string] -and [string]::IsNullOrWhiteSpace($Value.$field))) {
            throw "Missing field '$field': $Label"
        }
    }
}

function Resolve-UdkBuildPath([string]$Root, [string]$Base, [string]$Path, [switch]$Existing) {
    if ([string]::IsNullOrWhiteSpace($Path) -or [IO.Path]::IsPathRooted($Path)) {
        throw "Expected a relative path: $Path"
    }
    $boundary = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $resolved = [IO.Path]::GetFullPath((Join-Path $Base $Path))
    if ($resolved -ine $boundary -and -not $resolved.StartsWith($boundary + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escapes its root: $Path"
    }
    if ($Existing -and -not (Test-Path -LiteralPath $resolved)) {
        throw "Missing path: $resolved"
    }
    return $resolved
}

function Read-UdkBuildJson([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing JSON file: $Path"
    }
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Assert-UdkBuildName([string]$Name) {
    if ($Name -cnotmatch '^[A-Za-z][A-Za-z0-9_.-]*$' -or $Name.EndsWith('.')) {
        throw "Invalid build name: $Name"
    }
}

function Test-UdkSchemaVersion($Value, [int]$Expected) {
    return (($Value -is [int] -or $Value -is [long]) -and $Value -eq $Expected)
}

function Get-UdkPackagePlan([string]$RepositoryPath, [string]$PackagePath, [string]$DeliveryName, [hashtable]$ReleaseStack = @{}) {
    # Check all settings before running build tools.
    $root = (Resolve-Path -LiteralPath $RepositoryPath).Path
    $packageFile = Resolve-UdkBuildPath $root $root $PackagePath -Existing
    $packageRoot = Split-Path -Parent $packageFile
    $package = Read-UdkBuildJson $packageFile
    Assert-UdkFields $package @('schemaVersion', 'name', 'versionSource', 'projects', 'contents', 'deliveries', 'releaseDependencies') @('schemaVersion', 'name', 'versionSource', 'projects', 'contents', 'deliveries') $packageFile
    if (-not (Test-UdkSchemaVersion $package.schemaVersion 2)) {
        throw 'Unsupported package schemaVersion.'
    }
    Assert-UdkBuildName $package.name
    if ($package.contents -isnot [array] -or -not $package.contents.Count) {
        throw 'Package contents must be a nonempty array.'
    }
    if ($package.deliveries -isnot [pscustomobject] -or -not @($package.deliveries.PSObject.Properties).Count) {
        throw 'deliveries must be a nonempty object.'
    }
    $deliveryNames = @($package.deliveries.PSObject.Properties.Name)
    if (-not $DeliveryName) {
        $DeliveryName = if ('NuGet' -in $deliveryNames) {
            'NuGet'
        } elseif ($deliveryNames.Count -eq 1) {
            $deliveryNames[0]
        } else {
            throw 'Select -Delivery explicitly.'
        }
    }
    if ($DeliveryName -notin $deliveryNames) {
        throw "Unknown delivery: $DeliveryName"
    }
    $releaseKey = $packageFile + '|' + $DeliveryName
    if ($ReleaseStack.ContainsKey($releaseKey)) {
        throw "Package release dependency cycle: $releaseKey"
    }
    $nextStack = $ReleaseStack.Clone(); $nextStack[$releaseKey] = $true
    if ($package.versionSource -is [string]) {
        $versionSource = [pscustomobject]@{
            path=$package.versionSource
            format='json'
            property='version'
        }
    }
    else {
        Assert-UdkFields $package.versionSource @('path','format','property') @('path','format','property') 'versionSource'
        $versionSource=$package.versionSource
    }
    $versionPath = Resolve-UdkBuildPath $root $packageRoot $versionSource.path -Existing
    $versionData = switch ($versionSource.format) {
        'json' {
            Read-UdkBuildJson $versionPath
        }
        'properties' {
            ConvertFrom-StringData (Get-Content -LiteralPath $versionPath -Raw)
        }
        default {
            throw 'Unsupported version source format.'
        }
    }
    $version = $versionData.($versionSource.property)
    if ($version -isnot [string] -or $version -notmatch '^\d+\.\d+\.\d+(?:\.\d+)?(?:[-+][A-Za-z0-9.-]+)?$') {
        throw 'Invalid package version.'
    }
    $deliveryPath = Resolve-UdkBuildPath $root $packageRoot $package.deliveries.$DeliveryName -Existing
    $delivery = Read-UdkBuildJson $deliveryPath
    $nuspec = $null
    if (-not (Test-UdkSchemaVersion $delivery.schemaVersion 1)) {
        throw 'Unsupported delivery schemaVersion.'
    }
    switch ($delivery.adapter) {
        'nuget' {
            Assert-UdkFields $delivery @('schemaVersion','adapter','id','supportedPlatforms','nuspec','noWarn','dependencies','dependencySource','integration','supportedRuntimes','preparationScript','stagingScript','dependencyName','noDefaultExcludes') @('schemaVersion','adapter','id','supportedPlatforms','nuspec') $deliveryPath
            Assert-UdkBuildName $delivery.id
            if ($delivery.supportedPlatforms -isnot [array] -or $delivery.supportedPlatforms.Count -ne 1 -or $delivery.supportedPlatforms[0] -cne 'Windows') {
                throw 'This NuGet profile requires Windows delivery.'
            }
            if ($delivery.noWarn -and ($delivery.noWarn -isnot [array] -or @($delivery.noWarn | Where-Object {
                $_ -cnotmatch '^NU\d{4}$'
                    }).Count)) {
                throw 'Invalid NuGet noWarn list.'
            }
            $nuspec = Resolve-UdkBuildPath $packageRoot (Split-Path -Parent $deliveryPath) $delivery.nuspec -Existing
            [xml]$spec = Get-Content -LiteralPath $nuspec -Raw
            if ($delivery.dependencySource -and $delivery.dependencySource -cne 'udk-component') {
                throw 'Unknown dependencySource.'
            }
            if ($delivery.dependencySource -and $null -ne $delivery.dependencies) {
                throw 'Use dependencies or dependencySource, not both.'
            }
            if ($null -ne $delivery.dependencies) {
                if ($delivery.dependencies -isnot [array] -or -not ([IO.File]::ReadAllText($nuspec).Contains('{{DEPENDENCIES}}'))) {
                    throw 'NuGet dependencies require an array and a nuspec placeholder.'
                }
                $dependencyIds = @{}
                foreach ($dependency in $delivery.dependencies) {
                    Assert-UdkFields $dependency @('id','version') @('id','version') 'NuGet dependency'
                    Assert-UdkBuildName $dependency.id
                    if ($dependency.version -isnot [string] -or $dependency.version -cnotmatch '^\d+\.\d+\.\d+(?:\.\d+)?(?:-[A-Za-z0-9.-]+)?$') {
                        throw 'NuGet dependency requires an exact version.'
                    }
                    if ($dependencyIds.ContainsKey($dependency.id) -or $dependency.id -ieq $delivery.id) {
                        throw 'Duplicate or self NuGet dependency.'
                    }
                    $dependencyIds[$dependency.id]=$true
                }
            } elseif (-not $delivery.dependencySource -and [IO.File]::ReadAllText($nuspec).Contains('{{DEPENDENCIES}}')) {
                throw 'The nuspec dependencies placeholder requires a dependencies array.'
            }
            if ($spec.package.metadata.id -cne $delivery.id -or $spec.package.metadata.version -cne '{{VERSION}}') {
                throw 'NuGet metadata does not match delivery ID or version placeholder.'
            }
        }
        {
            $_ -in @('maven-prefab','maven-repository')
        } {
            Assert-UdkFields $delivery @('schemaVersion','adapter','groupId','artifactId','artifactPrefix') @('schemaVersion','adapter','groupId') $deliveryPath
            if ($delivery.groupId -cnotmatch '^[a-z][a-z0-9.]+$') {
                throw 'Invalid Maven groupId.'
            }
            $artifactName = if ($delivery.adapter -eq 'maven-prefab') {
                $delivery.artifactPrefix
            } else {
                $delivery.artifactId
            }
            if ($artifactName -cnotmatch '^[a-z][a-z0-9-]+$') {
                throw 'Invalid Maven artifact name.'
            }
        }
        default {
            throw "Unsupported delivery adapter: $($delivery.adapter)"
        }
    }
    $definitions = [Collections.Generic.List[object]]::new()
    $projectScope = $null
    if ($package.projects -is [string]) {
        $manifestPath = Resolve-UdkBuildPath $root $packageRoot $package.projects -Existing
        $manifest = Read-UdkBuildJson $manifestPath
        Assert-UdkFields $manifest @('schemaVersion', 'includes') @('schemaVersion', 'includes') $manifestPath
        if (-not (Test-UdkSchemaVersion $manifest.schemaVersion 1) -or $manifest.includes -isnot [array] -or -not $manifest.includes.Count) {
            throw 'Invalid build project registry.'
        }
        foreach ($include in $manifest.includes) {
            $projectPath = Resolve-UdkBuildPath $root (Split-Path -Parent $manifestPath) $include -Existing
            $definitions.Add([pscustomobject]@{
                Label = $projectPath
                Project = (Read-UdkBuildJson $projectPath)
            })
        }
    } elseif ($package.projects -is [pscustomobject] -and @($package.projects.PSObject.Properties).Count) {
        # Use object keys as local names. Give each package its own work directory.
        $projectScope = $package.name
        foreach ($entry in $package.projects.PSObject.Properties) {
            Assert-UdkBuildName $entry.Name
            if ($entry.Value -isnot [pscustomobject]) {
                throw "Expected a project object: $($entry.Name)"
            }
            $project = [pscustomobject]@{
                schemaVersion = 1
                name = $entry.Name
            }
            foreach ($field in $entry.Value.PSObject.Properties) {
                if ($field.Name -in @('name', 'schemaVersion')) {
                    throw "Inline project name and schemaVersion are implicit: $($entry.Name)"
                }
                $project | Add-Member -NotePropertyName $field.Name -NotePropertyValue $field.Value
            }
            $definitions.Add([pscustomobject]@{
                Label = "$packageFile/projects/$($entry.Name)"
                Project = $project
            })
        }
    } else {
        throw 'projects must be a registry path or a nonempty object of local project definitions.'
    }
    $projects = @{}
    foreach ($definition in $definitions) {
        $projectPath = $definition.Label
        $project = $definition.Project
        $common = @('schemaVersion', 'name', 'adapter', 'dependencies', 'artifacts')
        $specific = switch ($project.adapter) {
            'dotnet' {
                @('project', 'operation', 'configuration', 'runtime', 'selfContained')
            }
            'component-sources' {
                @('component', 'sourceRoot', 'includeRoot', 'publicHeaders', 'headerDestination', 'sourceDestination', 'manifestDestination')
            }
            {
                $_ -in @('cmake-install','cmake-build')
            } {
                @('sourceDirectory','generator','architecture','configurations','parallel','variables','preparation')
            }
            'udk-native' {
                @('component','generator')
            }
            'udk-prefab' {
                @('component','configuration','abis','apiLevel','toolchain')
            }
            'gradle-publish' {
                @('projectDirectory','tasks','toolchain','refreshDependencies')
            }
            'files' {
                @('mappings')
            }
            'nuget-restore' {
                @('id', 'version', 'sources')
            }
            default {
                throw "Unknown project adapter: $($project.adapter)"
            }
        }
        Assert-UdkFields $project ($common + $specific) @('schemaVersion', 'name', 'adapter', 'artifacts') $projectPath
        if (-not (Test-UdkSchemaVersion $project.schemaVersion 1)) {
            throw "Unsupported project schemaVersion: $projectPath"
        }
        Assert-UdkBuildName $project.name
        if ($projects.ContainsKey($project.name)) {
            throw "Duplicate project: $($project.name)"
        }
        if ($null -ne $project.dependencies -and $project.dependencies -isnot [array]) {
            throw 'Project dependencies must be an array.'
        }
        if ($project.artifacts -isnot [pscustomobject] -or -not @($project.artifacts.PSObject.Properties).Count) {
            throw 'Project requires named artifacts.'
        }
        $roots = @('output')
        switch ($project.adapter) {
            'files' {
                if ($project.mappings -isnot [array] -or -not $project.mappings.Count) {
                    throw 'files requires a nonempty mappings array.'
                }
                foreach ($mapping in $project.mappings) {
                    Assert-UdkFields $mapping @('source', 'destination') @('source', 'destination') 'file mapping'
                    [void](Resolve-UdkBuildPath $root $root $mapping.source -Existing)
                    [void](Resolve-UdkBuildPath $root $root $mapping.destination)
                }
            }
            'nuget-restore' {
                Assert-UdkFields $project ($common + $specific) @('id', 'version') $projectPath
                Assert-UdkBuildName $project.id
                if ($project.version -isnot [string] -or $project.version -notmatch '^\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?$') {
                    throw 'nuget-restore requires an exact package version.'
                }
                if ($null -ne $project.sources -and $project.sources -isnot [array]) {
                    throw 'NuGet sources must be an array.'
                }
                $roots = @('package')
            }
            'dotnet' {
                Assert-UdkFields $project ($common + $specific) @('project', 'operation', 'configuration') $projectPath
                [void](Resolve-UdkBuildPath $root $root $project.project -Existing)
                if ($project.operation -cnotin @('build', 'publish') -or $project.configuration -cnotin @('Debug', 'Release')) {
                    throw 'Invalid dotnet operation or configuration.'
                }
                if ($null -ne $project.selfContained -and ($project.selfContained -isnot [bool] -or -not $project.runtime -or $project.operation -ne 'publish')) {
                    throw 'selfContained requires publish with a runtime.'
                }
            }
            'component-sources' {
                Assert-UdkFields $project ($common + $specific) $specific $projectPath
                foreach ($field in @('component', 'sourceRoot', 'includeRoot')) {
                    [void](Resolve-UdkBuildPath $root $root $project.$field -Existing)
                }
                $component = Read-UdkBuildJson (Join-Path $root $project.component)
                if ($component.headers -isnot [array] -or $component.sources -isnot [array] -or $component.platformSources) {
                    throw 'Source distribution requires headers/sources arrays without platformSources.'
                }
                if ($project.publicHeaders -isnot [array] -or -not $project.publicHeaders.Count) {
                    throw 'publicHeaders must be a nonempty array.'
                }
                foreach ($field in @('headerDestination', 'sourceDestination', 'manifestDestination')) {
                    [void](Resolve-UdkBuildPath $root $root $project.$field)
                }
            }
            {
                $_ -in @('cmake-install','cmake-build')
            } {
                Assert-UdkFields $project ($common + $specific) @('sourceDirectory', 'generator', 'architecture', 'configurations', 'parallel', 'variables') $projectPath
                [void](Resolve-UdkBuildPath $root $root $project.sourceDirectory -Existing)
                if ($project.configurations -isnot [array] -or -not $project.configurations.Count -or @($project.configurations | Where-Object {
                    $_ -cnotin @('Debug', 'Release')
                    }).Count) {
                    throw 'Invalid CMake configurations.'
                }
                if (($project.parallel -isnot [int] -and $project.parallel -isnot [long]) -or $project.parallel -lt 1) {
                    throw 'Invalid CMake parallel count.'
                }
                if ($project.variables -isnot [pscustomobject] -or $project.variables.PSObject.Properties.Name -contains 'CMAKE_INSTALL_PREFIX') {
                    throw 'Invalid CMake variables; install prefix is owned by the adapter.'
                }
                $roots = if ($project.adapter -eq 'cmake-install') {
                    @('install','build')
                } else {
                    @('build')
                }
                if ($project.preparation) {
                    Assert-UdkFields $project.preparation @('script', 'parameters', 'properties') @('script', 'parameters', 'properties') 'preparation'
                    [void](Resolve-UdkBuildPath $root $root $project.preparation.script -Existing)
                    if ($project.preparation.parameters -isnot [pscustomobject] -or $project.preparation.properties -isnot [array] -or -not $project.preparation.properties.Count) {
                        throw 'Invalid preparation parameters or properties.'
                    }
                    foreach ($parameter in $project.preparation.parameters.PSObject.Properties.Name) {
                        if ($parameter -in @('RepositoryPath', 'WorkDirectory', 'Configurations', 'Generator')) {
                            throw "Reserved preparation parameter: $parameter"
                        }
                    }
                    foreach ($property in $project.preparation.properties) {
                        Assert-UdkBuildName $property
                    }
                    $roots += $project.preparation.properties
                }
            }
        }
        if ($project.adapter -in @('udk-native','udk-prefab')) {
            Assert-UdkFields $project ($common + $specific) $specific $projectPath
            Assert-UdkBuildName $project.component
            [void](Resolve-UdkBuildPath $root $root 'Components.json' -Existing)
            if ($project.adapter -eq 'udk-prefab') {
                [void](Resolve-UdkBuildPath $root $root $project.toolchain -Existing)
                if ($project.configuration -notin @('Debug','Release') -or $project.abis -isnot [array] -or -not $project.abis.Count -or @($project.abis | Where-Object {
                    $_ -notin @('arm64-v8a','x86_64')
                    }).Count -or $project.apiLevel -lt 24 -or $project.apiLevel -gt 35) {
                    throw 'Invalid Android Prefab profile.'
                }
            }
        }
        if ($project.adapter -eq 'gradle-publish') {
            Assert-UdkFields $project ($common + $specific) @('projectDirectory','tasks','toolchain') $projectPath
            [void](Resolve-UdkBuildPath $root $root $project.projectDirectory -Existing)
            [void](Resolve-UdkBuildPath $root $root $project.toolchain -Existing)
            if ($project.tasks -isnot [array] -or -not $project.tasks.Count) {
                throw 'Gradle tasks must be a nonempty array.'
            }
        }
        foreach ($artifact in $project.artifacts.PSObject.Properties) {
            Assert-UdkBuildName $artifact.Name
            Assert-UdkFields $artifact.Value @('root', 'path') @('root', 'path') "artifact $($artifact.Name)"
            if ($artifact.Value.root -cnotin $roots) {
                throw "Unknown artifact root: $($artifact.Value.root)"
            }
            [void](Resolve-UdkBuildPath $root $root $artifact.Value.path)
        }
        $projects[$project.name] = $project
    }
    $selectedContents = [Collections.Generic.List[object]]::new()
    foreach ($entry in $package.contents) {
        if ($null -ne $entry.deliveries) {
            if ($entry.deliveries -isnot [array] -or -not $entry.deliveries.Count -or @($entry.deliveries | Where-Object {
                $_ -notin $deliveryNames
                }).Count) {
                throw 'Invalid contents deliveries filter.'
            }
            if ($DeliveryName -notin $entry.deliveries) {
                continue
            }
        }
        $selectedContents.Add($entry)
        if ($entry.PSObject.Properties.Name -contains 'file') {
            Assert-UdkFields $entry @('file', 'destination','deliveries') @('file', 'destination') 'file content'
            $file = Resolve-UdkBuildPath $root $packageRoot $entry.file -Existing
            if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
                throw 'File content must reference a file.'
            }
        } else {
            Assert-UdkFields $entry @('project', 'artifact', 'destination', 'rename','deliveries') @('project', 'artifact', 'destination') 'artifact content'
            if (-not $projects.ContainsKey($entry.project) -or $null -eq $projects[$entry.project].artifacts.($entry.artifact)) {
                throw "Unknown project artifact: $($entry.project)/$($entry.artifact)"
            }
            if ($entry.rename -and ($entry.rename -match '[/\\]' -or $entry.rename -in @('.', '..'))) {
                throw 'rename must be a file name.'
            }
        }
        [void](Resolve-UdkBuildPath $root $root $entry.destination)
    }
    if (-not $selectedContents.Count) {
        throw 'No contents selected for this delivery.'
    }
    $package.contents = @($selectedContents.ToArray())
    $order = [Collections.Generic.List[string]]::new()
    $states = @{}
    function Visit-UdkBuildProject([string]$Name) {
        if (-not $projects.ContainsKey($Name)) {
            throw "Unknown project dependency: $Name"
        }
        if ($states[$Name] -eq 'visiting') {
            throw "Project dependency cycle: $Name"
        }
        if ($states[$Name] -eq 'done') {
            return
        }
        $states[$Name] = 'visiting'
        foreach ($dependency in $projects[$Name].dependencies) {
            Visit-UdkBuildProject $dependency
        }
        $states[$Name] = 'done'
        $order.Add($Name)
    }
    foreach ($entry in $package.contents) {
        if ($entry.project) {
            Visit-UdkBuildProject $entry.project
        }
    }
    $releaseDependencies = [Collections.Generic.List[object]]::new()
    if ($null -ne $package.releaseDependencies -and $package.releaseDependencies -isnot [array]) {
        throw 'releaseDependencies must be an array.'
    }
    foreach ($dependency in $package.releaseDependencies) {
        Assert-UdkFields $dependency @('package','delivery','when') @('package') 'release dependency'
        if ($null -ne $dependency.when) {
            if ($dependency.when -isnot [array] -or @($dependency.when | Where-Object {
                $_ -notin $deliveryNames
                }).Count) {
                throw 'Invalid release dependency delivery filter.'
            }
            if ($DeliveryName -notin $dependency.when) {
                continue
            }
        }
        $dependencyPath = Resolve-UdkBuildPath $root $packageRoot $dependency.package -Existing
        $dependencyDelivery = if ($dependency.delivery) {
            $dependency.delivery
        } else {
            $DeliveryName
        }
        $releaseDependencies.Add((Get-UdkPackagePlan $root $dependencyPath.Substring($root.Length+1) $dependencyDelivery $nextStack))
    }
    return [pscustomobject]@{
        RepositoryPath = $root
        PackagePath = $packageFile
        PackageRoot = $packageRoot
        DeliveryName = $DeliveryName
        ReleaseDependencies = @($releaseDependencies.ToArray())
        Package = $package
        Version = $version
        Delivery = $delivery
        Nuspec = $nuspec
        Projects = $projects
        ProjectScope = $projectScope
        Order = @($order.ToArray())
    }
}