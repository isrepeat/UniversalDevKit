function Format-UdkXmlAttributes {
    param([string]$Content)

    $newline = if ($Content.Contains("`r`n")) {
        "`r`n"
    } else {
        "`n"
    }
    # Skip comments and CDATA entirely; > inside an attribute does not end the tag.
    $pattern = '<!--[\s\S]*?-->|<!\[CDATA\[[\s\S]*?\]\]>|<[A-Za-z_:][\w:.-]*(?:[^<>"'']|"[^"]*"|''[^'']*'')*>'
    $attributePattern = '[\w:.-]+\s*=\s*(?:"[^"]*"|''[^'']*'')'
    return [regex]::Replace($Content, $pattern, [Text.RegularExpressions.MatchEvaluator]{
        param($tag)
        if ($tag.Value.StartsWith('<!')) {
            return $tag.Value
        }
        $name = [regex]::Match($tag.Value, '^<[\w:.-]+').Value
        $attributes = [regex]::Matches($tag.Value.Substring($name.Length), $attributePattern)
        if ($attributes.Count -lt 2) {
            return $tag.Value
        }

        # Align continuation lines with the first attribute, accounting for the tag position.
        $lineStart = $Content.LastIndexOf("`n", $tag.Index) + 1
        $indent = ' ' * ($tag.Index - $lineStart + $name.Length + 1)
        $parts = @($attributes | ForEach-Object { $_.Value })
        $closing = if ($tag.Value -match '/\s*>$') {
            ' />'
        } else {
            '>'
        }
        return $name + ' ' + ($parts -join ($newline + $indent)) + $closing
    })
}