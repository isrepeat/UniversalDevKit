#include "../../../Includes/XamlRuntime/UniversalDevKit/XamlRuntime/RuntimeMarkup/XamlSchemaValidator.h"

#include "../../../Includes/XamlRuntime/UniversalDevKit/XamlRuntime/RuntimeMarkup/RuntimeDiagnostics.h"
#include "../../../Includes/XamlRuntime/UniversalDevKit/XamlRuntime/ElementBuilder.h"

#include <algorithm>
#include <sstream>
#include <cmath>

namespace xaml::runtime::_details {
    void ValidateTrack(const std::string& value, const XamlSourceLocation& location) {
        if (value == "Auto" || value == "*") {
            return;
        }
        const auto number = !value.empty() && value.back() == '%' ? value.substr(0, value.size() - 1) : value;
        try {
            size_t count = 0;
            const auto parsed = std::stof(number, &count);
            if (count != number.size() || !std::isfinite(parsed) || parsed < 0) {
                throw std::invalid_argument("number");
            }
        } catch (const std::exception&) {
            throw RuntimeDiagnostic(location, "Invalid Grid definition '" + value + "'");
        }
    }

    void ValidateNode(
        const XamlElementNode& node,
        std::string_view xamlNamespace,
        std::string_view controlXmlNamespace,
        const std::set<std::string>& controls) {
        if (node.nameSpace != xamlNamespace && node.nameSpace != controlXmlNamespace) {
            throw RuntimeDiagnostic(node.location, "Unsupported namespace '" + node.nameSpace + "'");
        }
        const bool control = !controlXmlNamespace.empty() && node.nameSpace == controlXmlNamespace;
        if (control && controls.count(node.name) == 0) {
            throw RuntimeDiagnostic(node.location, "Native control '" + node.name + "' is not registered");
        }
        ElementType type;
        try {
            type = control ? ElementType::grid : ParseElementType(node.name);
        } catch (const std::exception& error) {
            throw RuntimeDiagnostic(node.location, error.what());
        }
        Element scratch(type);
        const auto names = SupportedAttributeNames(type);
        for (const auto& attribute : node.attributes) {
            if (attribute.nameSpace == "http://schemas.microsoft.com/winfx/2006/xaml"
                && (attribute.name == "Class" || attribute.name == "Name")) {
                continue;
            }
            try {
                if (!attribute.nameSpace.empty() || (std::find(names.begin(), names.end(), attribute.name) == names.end()
                    && !(control && attribute.name == "itemsSource"))) {
                    throw std::invalid_argument("Unsupported attribute '" + attribute.name + "' on " + node.name);
                }
                if (attribute.value.empty() || attribute.value.front() != '{') {
                    if (attribute.name == "rows" || attribute.name == "columns") {
                        std::istringstream input(attribute.value);
                        std::string track;
                        while (std::getline(input, track, ',')) {
                            ValidateTrack(track, attribute.location);
                        }
                    }
                    SetAttribute(scratch, attribute.name, attribute.value);
                }
            } catch (const std::exception& error) {
                throw RuntimeDiagnostic(attribute.location, error.what());
            }
        }
        std::set<std::string> properties;
        for (const auto& child : node.children) {
            const bool rows = child.name == "rowDefinitions" || child.name == "Grid.rowDefinitions";
            const bool columns = child.name == "columnDefinitions" || child.name == "Grid.columnDefinitions";
            const bool templateProperty = child.name == "ListView.ItemTemplate";
            const bool storyboards = child.name == node.name + ".Storyboards";
            const bool states = child.name == "VisualStateManager.VisualStateGroups";
            if (rows || columns || templateProperty || storyboards || states) {
                if (child.nameSpace != xamlNamespace || !child.attributes.empty()
                    || !properties.insert(rows ? "rows" : columns ? "columns" : child.name).second) {
                    throw RuntimeDiagnostic(child.location, "Invalid or duplicate property element");
                }
                if (rows || columns) {
                    if (type != ElementType::grid || control) {
                        throw RuntimeDiagnostic(child.location, "Grid definitions require a Grid");
                    }
                    std::string definition;
                    for (const auto& entry : child.children) {
                        if (entry.name != (rows ? "rowDefinition" : "columnDefinition") || !entry.children.empty()
                            || entry.attributes.size() != 1 || entry.attributes[0].name != (rows ? "height" : "width")) {
                            throw RuntimeDiagnostic(entry.location, "Invalid Grid definition");
                        }
                        ValidateTrack(entry.attributes[0].value, entry.attributes[0].location);
                        definition += (definition.empty() ? "" : " ") + entry.attributes[0].value;
                    }
                    continue;
                }
                if (templateProperty) {
                    if (type != ElementType::listView || child.children.size() != 1
                        || child.children[0].name != "DataTemplate" || child.children[0].children.size() != 1
                        || !child.children[0].attributes.empty()) {
                        throw RuntimeDiagnostic(child.location, "ListView.ItemTemplate requires one DataTemplate with one root");
                    }
                    ValidateNode(child.children[0].children[0], xamlNamespace, controlXmlNamespace, controls);
                }
                continue;
            }
            if (control) {
                throw RuntimeDiagnostic(child.location, "Native control content must be edited in its template file");
            }
            ValidateNode(child, xamlNamespace, controlXmlNamespace, controls);
            try {
                auto entry = std::make_unique<Element>(
                    !controlXmlNamespace.empty() && child.nameSpace == controlXmlNamespace
                    ? ElementType::grid : ParseElementType(child.name));
                ValidateChild(scratch, *entry);
                scratch.AddChild(std::move(entry));
            } catch (const std::exception& error) {
                throw RuntimeDiagnostic(child.location, error.what());
            }
        }
    }
}

namespace xaml::runtime {
    //
    // API
    //
    void XamlSchemaValidator::Validate(
        const XamlElementNode& root,
        std::string_view xamlNamespace,
        std::string_view controlXmlNamespace,
        const std::set<std::string>& controls) {
        _details::ValidateNode(root, xamlNamespace, controlXmlNamespace, controls);
    }
}