function SelectConsoleItem {
    param([string]$Title, [string[]]$Items, [hashtable]$MenuState = @{}, [string]$StateKey = $Title)

    if (-not $Items.Count) { throw 'Menu has no items.' }
    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) {
        throw 'Interactive selection requires a console. Use PowerShell parameters for non-interactive execution.'
    }
    $selected = 0
    # Запоминаем сам пункт, чтобы позиция сохранялась и при изменении порядка списка.
    if ($MenuState.ContainsKey($StateKey)) {
        $previousIndex = [Array]::IndexOf($Items, $MenuState[$StateKey])
        if ($previousIndex -ge 0) { $selected = $previousIndex }
    }
    $previousCursorVisible = [Console]::CursorVisible
    try {
        [Console]::CursorVisible = $false
        while ($true) {
            # Перерисовываем меню целиком, чтобы длинные пути не нарушали положение курсора.
            [Console]::Clear()
            Write-UdkConsoleText $Title Title
            Write-UdkConsoleText 'Up/Down: select | Enter: confirm | Backspace: back | Esc: cancel' Hint
            Write-Host ''
            for ($index = 0; $index -lt $Items.Count; $index++) {
                if ($index -eq $selected) {
                    Write-UdkConsoleText ('> ' + $Items[$index]) Focus
                }
                else { Write-UdkConsoleText ('  ' + $Items[$index]) }
            }
            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                'UpArrow' { $selected = ($selected + $Items.Count - 1) % $Items.Count }
                'DownArrow' { $selected = ($selected + 1) % $Items.Count }
                'Enter' {
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

function SelectConsoleComponents {
    param([string]$Title, [string[]]$Items, [hashtable]$InitialModes = @{}, [switch]$Removal, [hashtable]$Catalog = @{})

    if (-not $Items.Count) { throw 'No components available for this operation.' }
    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) {
        throw 'Interactive selection requires a console. Specify Components for non-interactive execution.'
    }
    $marked = @{}
    if (-not $Removal) {
        foreach ($name in $Items) {
            if ($InitialModes.ContainsKey($name)) { $marked[$name] = $InitialModes[$name] }
        }
    }
    $modes = @('Shared', 'Static', 'Dynamic')
    $selected = 0
    $column = 0
    $showDependencies = $false
    $previousCursorVisible = [Console]::CursorVisible
    try {
        [Console]::CursorVisible = $false
        while ($true) {
            # Пересчитываем предварительный набор, сохраняя самостоятельные подключения.
            $roots = if ($Removal) {
                @($InitialModes.Keys | Where-Object { -not $marked.ContainsKey($_) })
            }
            else { @(@($InitialModes.Keys) + @($marked.Keys) | Select-Object -Unique) }
            $requiredBy = @{}
            foreach ($rootName in $roots) {
                if (-not $Catalog.ContainsKey($rootName)) { continue }
                foreach ($dependency in @(Module.Udk.Connection\Resolve-UdkComponents @($rootName) $Catalog)) {
                    if ($dependency -eq $rootName) { continue }
                    if (-not $requiredBy.ContainsKey($dependency)) { $requiredBy[$dependency] = @() }
                    $requiredBy[$dependency] += $rootName
                }
            }
            $dependencies = @()
            $activeName = if ($selected -lt $Items.Count) { $Items[$selected] } else { $null }
            if ($showDependencies -and $activeName -and $Catalog.ContainsKey($activeName)) {
                $dependencies = @(Module.Udk.Connection\Resolve-UdkComponents @($activeName) $Catalog | Where-Object { $_ -ne $activeName })
            }
            [Console]::Clear()
            Write-UdkConsoleText $Title Title
            Write-UdkConsoleText 'Up/Down: component | Left/Right: mode | Space: toggle | Enter on Apply: confirm | Backspace: back | Esc: cancel' Hint
            Write-UdkConsoleText '/ or .: show/hide dependencies | *: required transitively, not explicitly selected' Hint
            Write-Host ''
            for ($index = 0; $index -le $Items.Count; $index++) {
                $rowRole = if ($index -eq $selected) { 'Focus' } else { 'Text' }
                $prefix = if ($index -eq $selected) { '> ' } else { '  ' }
                Write-UdkConsoleText $prefix $rowRole -NoNewline
                if ($index -eq $Items.Count) {
                    Write-UdkConsoleText 'Apply' $rowRole
                    continue
                }
                $name = $Items[$index]
                $transitive = $name -notin $roots -and $requiredBy.ContainsKey($name)
                $displayName = $name + $(if ($transitive) { '*' } else { '' })
                $nameRole = if ($name -in $dependencies) { 'Mark' } else { 'Text' }
                if ($Removal) {
                    $check = if ($marked.ContainsKey($name)) { 'x' } else { ' ' }
                    $markRole = if ($check -eq 'x') { 'Mark' } else { 'Text' }
                    Write-UdkConsoleText "[$check]" $markRole -NoNewline
                    if ($name -in $dependencies) { $rowRole = 'Mark' }
                    $modeText = if ($InitialModes.ContainsKey($name)) { $InitialModes[$name] } else { 'dependency' }
                    Write-UdkConsoleText " $displayName ($modeText)" $rowRole
                    continue
                }
                Write-UdkConsoleText $displayName.PadRight(24) $nameRole -NoNewline
                for ($modeIndex = 0; $modeIndex -lt $modes.Count; $modeIndex++) {
                    $focused = $index -eq $selected -and $modeIndex -eq $column
                    $check = if ($marked[$name] -eq $modes[$modeIndex]) { 'x' } else { ' ' }
                    $markRole = if ($check -eq 'x') { 'Mark' } else { 'Text' }
                    $modeRole = if ($focused) { 'Focus' } else { 'Text' }
                    $left = if ($focused) { '<' } else { ' ' }
                    $right = if ($focused) { '>' } else { ' ' }
                    Write-UdkConsoleText $left $modeRole -NoNewline
                    Write-UdkConsoleText "[$check]" $markRole -NoNewline
                    Write-UdkConsoleText (' ' + $modes[$modeIndex] + $right) $modeRole -NoNewline
                    if ($modeIndex -lt $modes.Count - 1) { Write-UdkConsoleText '  ' -NoNewline }
                }
                Write-Host ''
            }
            if ($showDependencies -and $activeName) {
                Write-Host ''
                Write-UdkConsoleText ("Dependencies: $activeName") Title
                # Два независимых вертикальных списка: строки не обозначают связь между колонками.
                $dependsOnNames = @(if ($dependencies.Count) { $dependencies } else { '(none)' })
                $requiredByNames = @(if ($requiredBy.ContainsKey($activeName)) { $requiredBy[$activeName] | Sort-Object -Unique } else { '(none)' })
                $dependsOnWidth = 'Depends on'.Length
                $requiredByWidth = 'Required by'.Length
                foreach ($name in $dependsOnNames) { $dependsOnWidth = [Math]::Max($dependsOnWidth, $name.Length) }
                foreach ($name in $requiredByNames) { $requiredByWidth = [Math]::Max($requiredByWidth, $name.Length) }
                $separator = '+-' + ('-' * $dependsOnWidth) + '-+-' + ('-' * $requiredByWidth) + '-+'
                Write-UdkConsoleText $separator Hint
                Write-UdkConsoleText ('| ' + 'Depends on'.PadRight($dependsOnWidth) + ' | ' + 'Required by'.PadRight($requiredByWidth) + ' |') Title
                Write-UdkConsoleText $separator Hint
                for ($rowIndex = 0; $rowIndex -lt [Math]::Max($dependsOnNames.Count, $requiredByNames.Count); $rowIndex++) {
                    $leftName = if ($rowIndex -lt $dependsOnNames.Count) { $dependsOnNames[$rowIndex] } else { '' }
                    $rightName = if ($rowIndex -lt $requiredByNames.Count) { $requiredByNames[$rowIndex] } else { '' }
                    Write-UdkConsoleText ('| ' + $leftName.PadRight($dependsOnWidth) + ' | ' + $rightName.PadRight($requiredByWidth) + ' |') Mark
                }
                Write-UdkConsoleText $separator Hint
            }
            $key = [Console]::ReadKey($true)
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
                        if ($Removal -and -not $InitialModes.ContainsKey($name)) { continue }
                        $mode = if ($Removal) { $InitialModes[$name] } else { $modes[$column] }
                        if ($marked[$name] -eq $mode) { $marked.Remove($name) }
                        else { $marked[$name] = $mode }
                    }
                }
                'Enter' {
                    if ($selected -eq $Items.Count -and $marked.Count) {
                        return $marked
                    }
                }
                'Escape' { throw 'Operation cancelled. No project changes were written.' }
                'Backspace' { return $null }
            }
        }
    }
    finally { [Console]::CursorVisible = $previousCursorVisible }
}