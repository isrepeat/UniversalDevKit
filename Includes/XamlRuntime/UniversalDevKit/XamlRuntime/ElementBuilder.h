#pragma once
#include "XamlLayout.h"
#include "Config.h"
#include "Export.h"

#include <string_view>
#include <vector>

namespace universaldevkit::xamlruntime {
    UNIVERSALDEVKIT_XAMLRUNTIME_API attr::Color ParseColor(std::string_view value);
    UNIVERSALDEVKIT_XAMLRUNTIME_API ElementType ParseElementType(std::string_view name);
    UNIVERSALDEVKIT_XAMLRUNTIME_API std::vector<std::string_view> SupportedAttributeNames(ElementType type);
    UNIVERSALDEVKIT_XAMLRUNTIME_API void SetAttribute(Element& element, std::string_view name, std::string_view value);
    UNIVERSALDEVKIT_XAMLRUNTIME_API void ValidateChild(const Element& parent, const Element& child);
}