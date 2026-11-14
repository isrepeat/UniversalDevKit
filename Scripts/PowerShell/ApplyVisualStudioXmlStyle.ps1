$ErrorActionPreference = 'Stop'
$settingsPath = Join-Path $PSScriptRoot '../../VisualStudio-XML-Warm.vssettings'
$settings = [xml][IO.File]::ReadAllText($settingsPath)
$palette = foreach ($entry in $settings.SelectNodes('//FontsAndColors/Categories/Category/Items/Item')) {
    $property = switch -Regex ($entry.Name) {
        '^XML ' { 'Foreground' }
        '^(Inactive )?Selected Text$' { 'Background' }
        default { throw "Unsupported editor color: $($entry.Name)" }
    }
    $color = $entry.GetAttribute($property)
    if ($color -cnotmatch '^0x00[0-9A-Fa-f]{6}$') {
        throw "Invalid $property color for $($entry.Name): $color"
    }
    [pscustomobject]@{
        Name = $entry.Name
        Property = $property
        Color = [Convert]::ToInt32($color.Substring(2), 16)
    }
}

try {
    $visualStudio = [Runtime.InteropServices.Marshal]::GetActiveObject('VisualStudio.DTE.18.0')
} catch {
    throw 'Open Visual Studio 2026 before applying the XML style.'
}
$items = $visualStudio.Properties('FontsAndColors', 'TextEditor').Item('FontsAndColorsItems').Object
foreach ($entry in $palette) {
    $item = $items.Item($entry.Name)
    $item.($entry.Property) = $entry.Color
    if ($item.($entry.Property) -ne $entry.Color) {
        throw "Visual Studio did not apply the color for $($entry.Name)."
    }
}
Write-Output "Applied $($palette.Count) editor colors in Visual Studio."