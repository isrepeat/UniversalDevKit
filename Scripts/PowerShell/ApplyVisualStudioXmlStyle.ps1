$ErrorActionPreference = 'Stop'
$settingsPath = Join-Path $PSScriptRoot '../../VisualStudio-XML-Warm.vssettings'
$settings = [xml][IO.File]::ReadAllText($settingsPath)
$managedColors = [ordered]@{
    'XML Name' = 'Foreground'
    'XML Attribute' = 'Foreground'
    'XML Attribute Value' = 'Foreground'
    'XML Attribute Quotes' = 'Foreground'
    'XML Text' = 'Foreground'
    'XML Delimiter' = 'Foreground'
    'XML Comment' = 'Foreground'
    'Selected Text' = 'Background'
    'Inactive Selected Text' = 'Background'
}
$palette = @{}
foreach ($entry in $settings.SelectNodes('//FontsAndColors/Categories/Category/Items/Item')) {
    $name = $entry.GetAttribute('Name')
    $property = $managedColors[$name]
    if (-not $property) { throw "Unsupported editor color: $name" }
    if ($palette.ContainsKey($name)) { throw "Duplicate editor color: $name" }
    $color = $entry.GetAttribute($property)
    if ($color -cnotmatch '^0x00[0-9A-Fa-f]{6}$') {
        throw "Invalid $property color for $($entry.Name): $color"
    }
    $palette[$name] = [Convert]::ToInt32($color.Substring(2), 16)
}

try {
    $visualStudio = [Runtime.InteropServices.Marshal]::GetActiveObject('VisualStudio.DTE.18.0')
} catch {
    throw 'Open Visual Studio 2026 before applying the XML style.'
}
$items = $visualStudio.Properties('FontsAndColors', 'TextEditor').Item('FontsAndColorsItems').Object
# Visual Studio uses this indexed color to clear the color override.
$themeDefault = 0x02000000
foreach ($entry in $managedColors.GetEnumerator()) {
    $name = $entry.Key
    $property = $entry.Value
    $item = $items.Item($name)
    if ($palette.ContainsKey($name)) {
        $item.$property = $palette[$name]
        if ($item.$property -ne $palette[$name]) {
            throw "Visual Studio did not apply the color for $name."
        }
    } else {
        $item.$property = $themeDefault
    }
}
Write-Output "Applied $($palette.Count) editor colors and reset $($managedColors.Count - $palette.Count) to the current Visual Studio theme."