#pragma once

#include <string_view>
#include <optional>
#include <cstdint>

namespace xaml {
    enum class XamlAttribute {
        id,
        dataContext,
        text,
        fontSize,
        lineHeight,
        fontFamily,
        fontWeight,
        textWrapping,
        source,
        tint,
        command,
        foreground,
        orientation,
        verticalAlignment,
        horizontalAlignment,
        contentAlignment,
        gridRow,
        gridColumn,
        rows,
        columns,
        background,
        activeBackground,
        borderBrush,
        activeBorderBrush,
        activeForeground,
        margin,
        padding,
        borderThickness,
        cornerRadius,
        width,
        height,
        isOn,
        visibility,
        isEnabled,
        opacity,
        itemsSource,
        renderer,
        verticalScrollBarVisibility,
        horizontalScrollBarVisibility,
        wireframe,
        count,
    };

    enum class XamlAttributeGroup : uint32_t {
        identity = 1 << 0,
        dataContext = 1 << 21,
        layout = 1 << 1,
        size = 1 << 2,
        gridPosition = 1 << 3,
        text = 1 << 4,
        source = 1 << 5,
        tint = 1 << 6,
        command = 1 << 7,
        orientation = 1 << 8,
        gridDefinitions = 1 << 9,
        background = 1 << 10,
        activeBackground = 1 << 16,
        border = 1 << 11,
        activeBorder = 1 << 17,
        activeForeground = 1 << 18,
        contentAlignment = 1 << 19,
        padding = 1 << 12,
        cornerRadius = 1 << 13,
        toggle = 1 << 14,
        itemsSource = 1 << 15,
        renderer = 1 << 20,
        scroll = 1 << 22,
        wireframe = 1 << 23,
    };

    std::optional<XamlAttribute> ParseXamlAttribute(std::string_view name);
    std::string_view XamlAttributeName(XamlAttribute attribute);
    XamlAttributeGroup XamlAttributeGroupOf(XamlAttribute attribute);
}