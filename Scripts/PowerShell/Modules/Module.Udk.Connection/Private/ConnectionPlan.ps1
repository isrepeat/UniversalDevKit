function Resolve-UdkLinkageGraph {
    param([string[]]$Components, [hashtable]$Modes, [hashtable]$ComponentRegistry)

    $resolvedModes = @{}
    $origins = @{}
    function VisitComponent([string]$Name, [string]$Mode, [string[]]$Stack) {
        if ($Name -cin $Stack) {
            throw ('Component dependency cycle: ' + (($Stack + $Name) -join ' -> '))
        }
        if (-not $ComponentRegistry.ContainsKey($Name)) {
            throw "Unknown component: $Name"
        }
        if ($Mode -cnotin @('Shared', 'Static', 'Dynamic')) {
            throw "Unsupported linkage for ${Name}: $Mode"
        }
        if ($ComponentRegistry[$Name].StateScope -eq 'process' -and $Mode -ne 'Dynamic') {
            throw "Component $Name has process state and requires Dynamic linkage."
        }
        if ($ComponentRegistry[$Name].Kind -eq 'headerOnly') {
            if (-not $Stack.Count -and $Mode -ne 'Shared') { throw "Header-only component $Name supports Shared only." }
            $Mode = 'Shared'
        }
        if ($resolvedModes.ContainsKey($Name)) {
            if ($resolvedModes[$Name] -cne $Mode) {
                throw "Conflicting linkage for ${Name}: $($resolvedModes[$Name]) via $($origins[$Name]); $Mode via $(($Stack + $Name) -join ' -> ')."
            }
            return
        }
        $resolvedModes[$Name] = $Mode
        $origins[$Name] = ($Stack + $Name) -join ' -> '
        foreach ($dependency in $ComponentRegistry[$Name].Dependencies) {
            $dependencyMode = if ($dependency.Linkage -eq 'dynamic') {
                'Dynamic'
            } elseif ($Mode -eq 'Shared') {
                'Shared'
            } elseif ($dependency.Linkage -eq 'static') {
                'Static'
            } else {
                $Mode
            }
            VisitComponent $dependency.Component $dependencyMode @($Stack + $Name)
        }
    }
    foreach ($name in $Components) { VisitComponent $name $Modes[$name] @() }

    # Resolve static dependencies and public DLL requirements for the final linker.
    $link = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    function VisitLink([string]$Name) {
        if ($resolvedModes[$Name] -ne 'Shared' -and -not $link.Add($Name)) {
            return
        }
        foreach ($dependency in $ComponentRegistry[$Name].Dependencies) {
            if ($resolvedModes[$Name] -in @('Shared', 'Static') -or $dependency.Visibility -eq 'public') {
                VisitLink $dependency.Component
            }
        }
    }
    foreach ($name in $Components) { VisitLink $name }

    # Import macros are required for roots and public dependencies only.
    $definitions = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    function VisitPublic([string]$Name) {
        if (-not $definitions.Add($Name)) {
            return
        }
        foreach ($dependency in $ComponentRegistry[$Name].Dependencies) {
            if ($resolvedModes[$Name] -eq 'Shared' -or $dependency.Visibility -eq 'public') {
                VisitPublic $dependency.Component
            }
        }
    }
    foreach ($name in $Components) { VisitPublic $name }
    return [pscustomobject]@{
        ResolvedModes = $resolvedModes
        ResolvedComponents = @($resolvedModes.Keys | Sort-Object)
        LinkComponents = @($link | Sort-Object)
        DefinitionComponents = @($definitions | Where-Object { $resolvedModes[$_] -eq 'Dynamic' } | Sort-Object)
        RequirementComponents = @($definitions | Sort-Object)
        SystemLibraryComponents = @($resolvedModes.Keys | Where-Object { $resolvedModes[$_] -eq 'Shared' -or ($resolvedModes[$_] -eq 'Static' -and $link.Contains($_)) } | Sort-Object)
        RuntimeComponents = @($resolvedModes.Keys | Where-Object { $resolvedModes[$_] -eq 'Dynamic' } | Sort-Object)
    }
}

function New-UdkConnectionPlan {
    param($Request, $State, [hashtable]$ComponentRegistry, [string]$RepositoryPath)

    $ProjectPath = $Request.ProjectPath
    $SolutionPath = $Request.SolutionPath
    $Components = @($Request.Components)
    $ComponentModes = $Request.ComponentModes
    $ProjectOnly = [bool]$Request.ProjectOnly
    $Disconnect = [bool]$Request.Disconnect
    $SolutionInjectorPath = $Request.SolutionInjectorPath
    $connectedComponents = @($State.Components)
    $graph = [pscustomobject]@{ LinkComponents = @(); DefinitionComponents = @(); RuntimeComponents = @() }
    $currentModes = $State.Modes
    $resolvedComponents = @()
    $resolvedModes = @{}

    # 1. Determine remaining roots, preserving components not selected for removal.
    $cleanupRequested = [bool]$Disconnect
    if ($cleanupRequested) {
        if ($Components) {
            foreach ($component in $Components) {
                if ($component -cnotin $connectedComponents) {
                    throw "Component is not explicitly connected: $component"
                }
            }
            $componentsToRemove = @($Components)
            $Components = @($connectedComponents | Where-Object { $_ -cnotin $componentsToRemove })
        }
        else {
            $Components = @()
        }
        $Disconnect = -not $Components.Count
    }
    else {
        $Components = @(@($connectedComponents) + @($Components) | Select-Object -Unique)
    }

    # 2. Resolve dependencies and validate modes for the remaining roots.
    if (-not $Disconnect) {
        $availableComponents = @($ComponentRegistry.Keys | Sort-Object)
        if (-not $Components) {
            $Components = if ('HeleprsTest' -cin $availableComponents) {
                @('HeleprsTest')
            } else {
                @($availableComponents[0])
            }
        }
        foreach ($component in $Components) {
            if ($component -cnotin $availableComponents) {
                throw "Unsupported component: $component"
            }
        }
        $Components = @($Components | Select-Object -Unique)
        $componentRegistry = $ComponentRegistry
        foreach ($name in $ComponentModes.Keys) {
            if ($name -cnotin $Components) {
                throw "Linkage specified for an unselected component: $name"
            }
        }
        # Validate modes before modifying the consumer or solution; treat legacy connections as Shared.
        $rootModes = @{}
        foreach ($name in $Components) {
            $mode = if ($ComponentModes.ContainsKey($name)) {
                $ComponentModes[$name]
            } elseif ($currentModes.ContainsKey($name)) {
                $currentModes[$name]
            } else {
                if ($ComponentRegistry[$name].StateScope -eq 'process') {
                    'Dynamic'
                } else {
                    'Shared'
                }
            }
            if ($mode -cnotin @('Shared', 'Static', 'Dynamic')) {
                throw "Unsupported linkage for ${name}: $mode"
            }
            if ($ProjectOnly -and $mode -ne 'Shared') {
                throw 'Static/Dynamic linkage requires SolutionPath.'
            }
            $rootModes[$name] = $mode
        }
        $graph = Resolve-UdkLinkageGraph $Components $rootModes $ComponentRegistry
        $resolvedModes = $graph.ResolvedModes
        $resolvedComponents = $graph.ResolvedComponents
    }

    return [pscustomobject]@{
        Request = $Request
        RepositoryPath = $RepositoryPath
        Components = @($Components)
        ResolvedComponents = @($resolvedComponents)
        ResolvedModes = $resolvedModes
        LinkComponents = @($graph.LinkComponents)
        DefinitionComponents = @($graph.DefinitionComponents)
        RequirementComponents = @($graph.RequirementComponents)
        SystemLibraryComponents = @($graph.SystemLibraryComponents)
        RuntimeComponents = @($graph.RuntimeComponents)
        Disconnect = [bool]$Disconnect
        CleanupRequested = $cleanupRequested
    }
}