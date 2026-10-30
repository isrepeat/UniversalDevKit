#pragma once

#include "XamlLayout.h"

#include <string_view>
#include <vector>

namespace xaml {
    attr::Color ParseColor(std::string_view value);
    ElementType ParseElementType(std::string_view name);
    std::vector<std::string_view> SupportedAttributeNames(ElementType type);
    void SetAttribute(Element& element, std::string_view name, std::string_view value);
    void ValidateChild(const Element& parent, const Element& child);
}