function Get-UdkRequirementDefinition {
    param($Component)

    $standard = 17
    $threads = $false
    if ($Component.PSObject.Properties['requirements']) {
        $settings = $Component.requirements
        if ($settings -isnot [pscustomobject]) {
            throw "requirements must be an object: $($Component.name)"
        }
        foreach ($field in $settings.PSObject.Properties.Name) {
            if ($field -cnotin @('cxxStandard', 'threads')) {
                throw "Unknown requirement: $field"
            }
        }
        if ($settings.PSObject.Properties['cxxStandard']) {
            if ($settings.cxxStandard -isnot [int] -and $settings.cxxStandard -isnot [long]) {
                throw 'cxxStandard must be an integer.'
            }
            if ($settings.cxxStandard -notin @(17, 20, 23)) {
                throw 'cxxStandard must be 17, 20 or 23.'
            }
            $standard = [int]$settings.cxxStandard
        }
        if ($settings.PSObject.Properties['threads']) {
            if ($settings.threads -isnot [bool]) {
                throw 'threads must be a boolean.'
            }
            $threads = $settings.threads
        }
    }
    $libraries = @{}
    if ($Component.PSObject.Properties['platformRequirements']) {
        if ($Component.platformRequirements -isnot [pscustomobject]) {
            throw 'platformRequirements must be an object.'
        }
        foreach ($entry in $Component.platformRequirements.PSObject.Properties) {
            if ($entry.Name -cnotin @('Windows', 'Linux', 'Android') -or $entry.Value -isnot [pscustomobject]) {
                throw "Invalid platform requirement: $($entry.Name)"
            }
            foreach ($field in $entry.Value.PSObject.Properties.Name) {
                if ($field -cne 'linkLibraries') {
                    throw "Unknown platform requirement: $field"
                }
            }
            if ($entry.Value.linkLibraries -isnot [Array]) {
                throw 'linkLibraries must be an array.'
            }
            foreach ($library in $entry.Value.linkLibraries) {
                if ($library -isnot [string] -or $library -cnotmatch '^[A-Za-z0-9_+.-]+$') {
                    throw "Invalid system library: $library"
                }
            }
            $libraries[$entry.Name] = @($entry.Value.linkLibraries | Select-Object -Unique)
        }
    }
    return [pscustomobject]@{ CxxStandard = $standard; Threads = $threads; Libraries = $libraries }
}

function Get-UdkRequirementItemsXml {
    param([string]$Name, $Requirements, [bool]$Compile, [bool]$System, [bool]$Threads = $false)

    $items = [Collections.Generic.List[string]]::new()
    if ($Compile) {
        $items.Add('    <__UniversalDevKitCompileRequirement Include="' + $Name + '">')
        $items.Add('      <MinimumStandard>' + $Requirements.CxxStandard + '</MinimumStandard>')
        $items.Add('    </__UniversalDevKitCompileRequirement>')
    }
    if ($Threads -and $Requirements.Threads) {
        $items.Add('    <__UniversalDevKitThreadRequirement Include="' + $Name + '" />')
    }
    if ($System) {
        foreach ($platform in @($Requirements.Libraries.Keys | Sort-Object)) {
            foreach ($library in $Requirements.Libraries[$platform]) {
                if ($platform -eq 'Windows') {
                    $file = if ($library.EndsWith('.lib', [StringComparison]::OrdinalIgnoreCase)) {
                        $library
                    } else {
                        $library + '.lib'
                    }
                    $items.Add('    <__UniversalDevKitSystemLibrary Include="' + $file + '" Condition="''$(UniversalDevKitTargetOS)'' == ''Windows''" />')
                } else {
                    $items.Add('    <__UniversalDevKitUnsupportedSystemRequirement Include="' + $Name + '" Condition="''$(UniversalDevKitTargetOS)'' == ''' + $platform + '''" />')
                }
            }
        }
    }
    return (@('  <ItemGroup>') + $items.ToArray() + @('  </ItemGroup>')) -join "`n"
}