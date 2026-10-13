function SelectConsoleItem {
    param([string]$Title, [string[]]$Items, [hashtable]$MenuState = @{}, [string]$StateKey = $Title, [hashtable]$UnavailableItems = @{})

    if (-not $Items.Count) {
        throw 'Menu has no items.'
    }
    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) {
        throw 'Interactive selection requires a console. Use PowerShell parameters for non-interactive execution.'
    }
    $selected = 0
    $notice = $null
    # Remember the selected item to preserve selection when list order changes.
    if ($MenuState.ContainsKey($StateKey)) {
        $previousIndex = [Array]::IndexOf($Items, $MenuState[$StateKey])
        if ($previousIndex -ge 0) {
            $selected = $previousIndex
        }
    }
    $previousCursorVisible = [Console]::CursorVisible
    try {
        [Console]::CursorVisible = $false
        while ($true) {
            # Redraw the entire menu so long paths do not disturb cursor positioning.
            [Console]::Clear()
            Write-UdkConsoleText $Title Title
            Write-UdkConsoleText 'Up/Down: select | Enter: confirm | Backspace: back | Esc: cancel' Hint
            Write-Host ''
            for ($index = 0; $index -lt $Items.Count; $index++) {
                if ($index -eq $selected) {
                    Write-UdkConsoleText ('> ' + $Items[$index]) Focus
                }
                else {
                    Write-UdkConsoleText ('  ' + $Items[$index])
                }
            }
            if ($notice) {
                Write-Host ''
                Write-UdkConsoleText $notice Hint
            }
            $key = [Console]::ReadKey($true)
            $notice = $null
            switch ($key.Key) {
                'UpArrow' { $selected = ($selected + $Items.Count - 1) % $Items.Count }
                'DownArrow' { $selected = ($selected + 1) % $Items.Count }
                'Enter' {
                    if ($UnavailableItems.ContainsKey($Items[$selected])) {
                        $notice = $UnavailableItems[$Items[$selected]]
                        continue
                    }
                    $MenuState[$StateKey] = $Items[$selected]
                    return $selected
                }
                'Backspace' {
                    $MenuState[$StateKey] = $Items[$selected]
                    return -1
                }
                'Escape' { throw 'Operation cancelled. No project changes were written.' }
            }
        }
    }
    finally { [Console]::CursorVisible = $previousCursorVisible }
}

function Get-UdkMenuModeConflict {
    param([hashtable]$InitialModes, [hashtable]$Marked, [hashtable]$ComponentRegistry, [string]$Name, [string]$Mode, [switch]$Removal, [switch]$ProjectOnly)

    # Validate the proposed selection using the same registry and plan as before writing.
    $previewModes = @{}
    foreach ($rootName in $InitialModes.Keys) { $previewModes[$rootName] = $InitialModes[$rootName] }
    foreach ($rootName in $Marked.Keys) {
        if ($Removal) {
            $previewModes.Remove($rootName)
        }
        else {
            $previewModes[$rootName] = $Marked[$rootName]
        }
    }
    if ($Name) {
        $previewModes[$Name] = $Mode
    }
    if (-not $previewModes.Count) {
        return $null
    }
    $request = [pscustomobject]@{
        Components = @($previewModes.Keys | Sort-Object)
        ComponentModes = $previewModes
        ProjectOnly = [bool]$ProjectOnly
        Disconnect = $false
    }
    try {
        Module.Udk.Connection\New-UdkConnectionPlan $request ([pscustomobject]@{ Components = @(); Modes = @{} }) $ComponentRegistry '' | Out-Null
        return $null
    }
    catch { return $_.Exception.Message }
}

function SelectConsoleComponents {
    param([string]$Title, [string[]]$Items, [hashtable]$InitialModes = @{}, [switch]$Removal, [hashtable]$ComponentRegistry = @{}, [switch]$ProjectOnly)

    if (-not $Items.Count) {
        throw 'No components available for this operation.'
    }
    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) {
        throw 'Interactive selection requires a console. Specify Components for non-interactive execution.'
    }
    $marked = @{}
    if (-not $Removal) {
        foreach ($name in $Items) {
            if ($InitialModes.ContainsKey($name)) {
                $marked[$name] = $InitialModes[$name]
            }
        }
    }
    $modes = @('Shared', 'Static', 'Dynamic')
    $selected = 0
    $column = 0
    $showDependencies = $false
    $notice = $null
    $previousCursorVisible = [Console]::CursorVisible
    try {
        [Console]::CursorVisible = $false
        while ($true) {
            # Recalculate blocked variants after each selection change.
            $blockedModes = @{}
            if (-not $Removal) {
                foreach ($name in $Items) {
                    foreach ($mode in $modes) {
                        $conflict = Get-UdkMenuModeConflict $InitialModes $marked $ComponentRegistry -Name $name -Mode $mode -ProjectOnly:$ProjectOnly
                        if ($conflict) {
                            $blockedModes["$name.$mode"] = $conflict
                        }
                    }
                }
            }
            $currentConflict = Get-UdkMenuModeConflict $InitialModes $marked $ComponentRegistry -Removal:$Removal -ProjectOnly:$ProjectOnly
            # Recalculate the preview while preserving independent connections.
            $roots = if ($Removal) {
                @($InitialModes.Keys | Where-Object { -not $marked.ContainsKey($_) })
            }
            else {
                @(@($InitialModes.Keys) + @($marked.Keys) | Select-Object -Unique)
            }
            $requiredBy = @{}
            foreach ($rootName in $roots) {
                if (-not $ComponentRegistry.ContainsKey($rootName)) {
                    continue
                }
                foreach ($dependency in @(Module.Udk.Connection\Resolve-UdkComponents @($rootName) $ComponentRegistry)) {
                    if ($dependency -eq $rootName) {
                        continue
                    }
                    if (-not $requiredBy.ContainsKey($dependency)) {
                        $requiredBy[$dependency] = @()
                    }
                    $requiredBy[$dependency] += $rootName
                }
            }
            $dependencies = @()
            $activeName = if ($selected -lt $Items.Count) {
                $Items[$selected]
            } else {
                $null
            }
            if ($showDependencies -and $activeName -and $ComponentRegistry.ContainsKey($activeName)) {
                $dependencies = @(Module.Udk.Connection\Resolve-UdkComponents @($activeName) $ComponentRegistry | Where-Object { $_ -ne $activeName })
            }
            if ($activeName -and $ComponentRegistry[$activeName].Kind -eq 'headerOnly') { $column = 0 }
            [Console]::Clear()
            Write-UdkConsoleText $Title Title
            Write-UdkConsoleText 'Up/Down: component | Left/Right: mode | Space: toggle | Enter on Apply: confirm | Backspace: back | Esc: cancel' Hint
            Write-UdkConsoleText '/ or .: show/hide dependencies | *: required transitively, not explicitly selected' Hint
            if (-not $Removal) {
                Write-UdkConsoleText 'Red [!]: unavailable mode. Focus it to see why.' Hint
            }
            Write-Host ''
            for ($index = 0; $index -le $Items.Count; $index++) {
                $rowRole = if ($index -eq $selected) {
                    'Focus'
                } else {
                    'Text'
                }
                $prefix = if ($index -eq $selected) {
                    '> '
                } else {
                    '  '
                }
                Write-UdkConsoleText $prefix $rowRole -NoNewline
                if ($index -eq $Items.Count) {
                    if ($currentConflict) {
                        $rowRole = 'Blocked'
                    }
                    Write-UdkConsoleText 'Apply' $rowRole
                    continue
                }
                $name = $Items[$index]
                $transitive = $name -notin $roots -and $requiredBy.ContainsKey($name)
                $displayName = $name + $(if ($transitive) {
                    '*'
                } else {
                    ''
                })
                $nameRole = if ($name -in $dependencies) {
                    'Mark'
                } else {
                    'Text'
                }
                if ($Removal) {
                    $check = if ($marked.ContainsKey($name)) {
                        'x'
                    } else {
                        ' '
                    }
                    $markRole = if ($check -eq 'x') {
                        'Mark'
                    } else {
                        'Text'
                    }
                    Write-UdkConsoleText "[$check]" $markRole -NoNewline
                    if ($name -in $dependencies) {
                        $rowRole = 'Mark'
                    }
                    $modeText = if ($InitialModes.ContainsKey($name)) {
                        $InitialModes[$name]
                    } else {
                        'dependency'
                    }
                    Write-UdkConsoleText " $displayName ($modeText)" $rowRole
                    continue
                }
                Write-UdkConsoleText $displayName.PadRight(24) $nameRole -NoNewline
                for ($modeIndex = 0; $modeIndex -lt $modes.Count; $modeIndex++) {
                    if ($ComponentRegistry[$name].Kind -eq 'headerOnly' -and $modes[$modeIndex] -ne 'Shared') { continue }
                    $focused = $index -eq $selected -and $modeIndex -eq $column
                    $check = if ($marked[$name] -eq $modes[$modeIndex]) {
                        'x'
                    } else {
                        ' '
                    }
                    $markRole = if ($check -eq 'x') {
                        'Mark'
                    } else {
                        'Text'
                    }
                    $modeRole = if ($focused) {
                        'Focus'
                    } else {
                        'Text'
                    }
                    if ($blockedModes.ContainsKey("$name.$($modes[$modeIndex])")) {
                        $modeRole = 'Blocked'
                        $markRole = 'Blocked'
                        if ($check -ne 'x') {
                            $check = '!'
                        }
                    }
                    $left = if ($focused) {
                        '<'
                    } else {
                        ' '
                    }
                    $right = if ($focused) {
                        '>'
                    } else {
                        ' '
                    }
                    Write-UdkConsoleText $left $modeRole -NoNewline
                    Write-UdkConsoleText "[$check]" $markRole -NoNewline
                    Write-UdkConsoleText (' ' + $modes[$modeIndex] + $right) $modeRole -NoNewline
                    if ($modeIndex -lt $modes.Count - 1) {
                        Write-UdkConsoleText '  ' -NoNewline
                    }
                }
                Write-Host ''
            }
            if ($showDependencies -and $activeName) {
                Write-Host ''
                Write-UdkConsoleText ("Dependencies: $activeName") Title
                # Two independent vertical lists; rows do not represent relationships between columns.
                $dependsOnNames = @(if ($dependencies.Count) {
                    $dependencies
                } else {
                    '(none)'
                })
                $requiredByNames = @(if ($requiredBy.ContainsKey($activeName)) {
                    $requiredBy[$activeName] | Sort-Object -Unique
                } else {
                    '(none)'
                })
                $dependsOnWidth = 'Depends on'.Length
                $requiredByWidth = 'Required by'.Length
                foreach ($name in $dependsOnNames) { $dependsOnWidth = [Math]::Max($dependsOnWidth, $name.Length) }
                foreach ($name in $requiredByNames) { $requiredByWidth = [Math]::Max($requiredByWidth, $name.Length) }
                $separator = '+-' + ('-' * $dependsOnWidth) + '-+-' + ('-' * $requiredByWidth) + '-+'
                Write-UdkConsoleText $separator Hint
                Write-UdkConsoleText ('| ' + 'Depends on'.PadRight($dependsOnWidth) + ' | ' + 'Required by'.PadRight($requiredByWidth) + ' |') Title
                Write-UdkConsoleText $separator Hint
                for ($rowIndex = 0; $rowIndex -lt [Math]::Max($dependsOnNames.Count, $requiredByNames.Count); $rowIndex++) {
                    $leftName = if ($rowIndex -lt $dependsOnNames.Count) {
                        $dependsOnNames[$rowIndex]
                    } else {
                        ''
                    }
                    $rightName = if ($rowIndex -lt $requiredByNames.Count) {
                        $requiredByNames[$rowIndex]
                    } else {
                        ''
                    }
                    Write-UdkConsoleText ('| ' + $leftName.PadRight($dependsOnWidth) + ' | ' + $rightName.PadRight($requiredByWidth) + ' |') Mark
                }
                Write-UdkConsoleText $separator Hint
            }
            $focusedConflict = if ($activeName -and -not $Removal) {
                $blockedModes["$activeName.$($modes[$column])"]
            } elseif ($selected -eq $Items.Count) {
                $currentConflict
            } else {
                $null
            }
            if ($focusedConflict) {
                Write-Host ''
                Write-UdkConsoleText $focusedConflict Blocked
            }
            if ($notice) {
                Write-Host ''
                Write-UdkConsoleText $notice Hint
            }
            $key = [Console]::ReadKey($true)
            $notice = $null
            if ($key.KeyChar -eq '/' -or $key.KeyChar -eq '.') {
                $showDependencies = -not $showDependencies
                continue
            }
            switch ($key.Key) {
                'UpArrow' { $selected = ($selected + $Items.Count) % ($Items.Count + 1) }
                'DownArrow' { $selected = ($selected + 1) % ($Items.Count + 1) }
                'LeftArrow' { $column = ($column + $modes.Count - 1) % $modes.Count }
                'RightArrow' { $column = ($column + 1) % $modes.Count }
                'Spacebar' {
                    if ($selected -lt $Items.Count) {
                        $name = $Items[$selected]
                        if ($Removal -and -not $InitialModes.ContainsKey($name)) {
                            $notice = 'This component is required transitively. Disconnect the components that require it.'
                            continue
                        }
                        $mode = if ($Removal) {
                            $InitialModes[$name]
                        } else {
                            $modes[$column]
                        }
                        if ($marked[$name] -eq $mode) {
                            $marked.Remove($name)
                        }
                        elseif (-not $Removal -and $blockedModes.ContainsKey("$name.$mode")) {
                            $notice = $blockedModes["$name.$mode"]
                        }
                        else {
                            $marked[$name] = $mode
                        }
                    }
                }
                'Enter' {
                    if ($selected -eq $Items.Count -and $marked.Count) {
                        if ($currentConflict) {
                            $notice = $currentConflict; continue
                        }
                        return $marked
                    }
                    $notice = if ($selected -eq $Items.Count) {
                        if ($Removal) {
                            'Select at least one component to disconnect using Space, then choose Apply.'
                        }
                        else {
                            'Select at least one component and its mode using Space, then choose Apply.'
                        }
                    }
                    else {
                        'Use Space to select this component. Move to Apply and press Enter to confirm.'
                    }
                }
                'Escape' { throw 'Operation cancelled. No project changes were written.' }
                'Backspace' { return $null }
            }
        }
    }
    finally { [Console]::CursorVisible = $previousCursorVisible }
}