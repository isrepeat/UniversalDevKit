function New-UdkConnectionPlan {
    param($Request, $State, [hashtable]$Catalog, [string]$RepositoryPath)

    $ProjectPath = $Request.ProjectPath
    $SolutionPath = $Request.SolutionPath
    $Components = @($Request.Components)
    $ComponentModes = $Request.ComponentModes
    $ProjectOnly = [bool]$Request.ProjectOnly
    $Disconnect = [bool]$Request.Disconnect
    $SolutionInjectorPath = $Request.SolutionInjectorPath
    $connectedComponents = @($State.Components)
    $currentModes = $State.Modes
    $resolvedComponents = @()
    $resolvedModes = @{}

    # 1. Получаем итоговый набор корней, сохраняя компоненты, не выбранные для удаления.
    $cleanupRequested = [bool]$Disconnect
    if ($cleanupRequested) {
        if ($Components) {
            foreach ($component in $Components) {
                if ($component -cnotin $connectedComponents) { throw "Component is not explicitly connected: $component" }
            }
            $componentsToRemove = @($Components)
            $Components = @($connectedComponents | Where-Object { $_ -cnotin $componentsToRemove })
        }
        else { $Components = @() }
        $Disconnect = -not $Components.Count
    }
    else {
        $Components = @(@($connectedComponents) + @($Components) | Select-Object -Unique)
    }

    # 2. Для оставшихся корней раскрываем зависимости и проверяем режимы.
    if (-not $Disconnect) {
        $availableComponents = @($Catalog.Keys | Sort-Object)
        if (-not $Components) {
            $Components = if ('Helpers' -cin $availableComponents) { @('Helpers') } else { @($availableComponents[0]) }
        }
        foreach ($component in $Components) {
            if ($component -cnotin $availableComponents) { throw "Unsupported component: $component" }
        }
        $Components = @($Components | Select-Object -Unique)
        $componentCatalog = $Catalog
        $resolvedComponents = @(Resolve-UdkComponents $Components $componentCatalog)
        foreach ($name in $ComponentModes.Keys) {
            if ($name -cnotin $Components) { throw "Linkage specified for an unselected component: $name" }
        }
        # Режимы проверяем до изменения consumer и решения; старые подключения считаем Shared.
        $resolvedModes = @{}
        foreach ($name in $Components) {
            $mode = if ($ComponentModes.ContainsKey($name)) { $ComponentModes[$name] } elseif ($currentModes.ContainsKey($name)) { $currentModes[$name] } else { 'Shared' }
            if ($mode -cnotin @('Shared', 'Static', 'Dynamic')) { throw "Unsupported linkage for ${name}: $mode" }
            if ($ProjectOnly -and $mode -ne 'Shared') { throw 'Static/Dynamic linkage requires SolutionPath.' }
            if ($mode -ne 'Shared' -and $componentCatalog[$name].Dependencies.Count) {
                throw "Compiled dependencies are not yet configured for ${name}; use Shared for this component."
            }
            foreach ($dependency in @(Resolve-UdkComponents @($name) $componentCatalog)) {
                if ($resolvedModes.ContainsKey($dependency) -and $resolvedModes[$dependency] -ne $mode) {
                    throw "Conflicting linkage for dependency: $dependency"
                }
                $resolvedModes[$dependency] = $mode
            }
        }
    }

    return [pscustomobject]@{
        Request = $Request
        RepositoryPath = $RepositoryPath
        Components = @($Components)
        ResolvedComponents = @($resolvedComponents)
        ResolvedModes = $resolvedModes
        Disconnect = [bool]$Disconnect
        CleanupRequested = $cleanupRequested
    }
}