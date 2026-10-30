#include "../../Includes/XamlRuntime/UniversalDevKit/XamlRuntime/XamlAttribute.h"

namespace universaldevkit::xamlruntime {
    namespace details {
        struct AttributeMapping {
            XamlAttribute attribute;
            XamlAttributeGroup group;
            std::string_view name;
        };

        constexpr AttributeMapping attributeMappings[] = {
            {XamlAttribute::id, XamlAttributeGroup::identity, "id"},
            {XamlAttribute::dataContext, XamlAttributeGroup::dataContext, "dataContext"},
            {XamlAttribute::text, XamlAttributeGroup::text, "text"},
            {XamlAttribute::fontSize, XamlAttributeGroup::text, "fontSize"},
            {XamlAttribute::lineHeight, XamlAttributeGroup::text, "lineHeight"},
            {XamlAttribute::fontFamily, XamlAttributeGroup::text, "fontFamily"},
            {XamlAttribute::fontWeight, XamlAttributeGroup::text, "fontWeight"},
            {XamlAttribute::textWrapping, XamlAttributeGroup::text, "textWrapping"},
            {XamlAttribute::source, XamlAttributeGroup::source, "source"},
            {XamlAttribute::tint, XamlAttributeGroup::tint, "tint"},
            {XamlAttribute::command, XamlAttributeGroup::command, "command"},
            {XamlAttribute::foreground, XamlAttributeGroup::text, "foreground"},
            {XamlAttribute::orientation, XamlAttributeGroup::orientation, "orientation"},
            {XamlAttribute::verticalAlignment, XamlAttributeGroup::layout, "verticalAlignment"},
            {XamlAttribute::horizontalAlignment, XamlAttributeGroup::layout, "horizontalAlignment"},
            {XamlAttribute::contentAlignment, XamlAttributeGroup::contentAlignment, "contentAlignment"},
            {XamlAttribute::gridRow, XamlAttributeGroup::gridPosition, "gridRow"},
            {XamlAttribute::gridColumn, XamlAttributeGroup::gridPosition, "gridColumn"},
            {XamlAttribute::rows, XamlAttributeGroup::gridDefinitions, "rows"},
            {XamlAttribute::columns, XamlAttributeGroup::gridDefinitions, "columns"},
            {XamlAttribute::background, XamlAttributeGroup::background, "background"},
            {XamlAttribute::activeBackground, XamlAttributeGroup::activeBackground, "activeBackground"},
            {XamlAttribute::borderBrush, XamlAttributeGroup::border, "borderBrush"},
            {XamlAttribute::activeBorderBrush, XamlAttributeGroup::activeBorder, "activeBorderBrush"},
            {XamlAttribute::activeForeground, XamlAttributeGroup::activeForeground, "activeForeground"},
            {XamlAttribute::margin, XamlAttributeGroup::layout, "margin"},
            {XamlAttribute::padding, XamlAttributeGroup::padding, "padding"},
            {XamlAttribute::borderThickness, XamlAttributeGroup::border, "borderThickness"},
            {XamlAttribute::cornerRadius, XamlAttributeGroup::cornerRadius, "cornerRadius"},
            {XamlAttribute::width, XamlAttributeGroup::size, "width"},
            {XamlAttribute::height, XamlAttributeGroup::size, "height"},
            {XamlAttribute::isOn, XamlAttributeGroup::toggle, "isOn"},
            {XamlAttribute::visibility, XamlAttributeGroup::layout, "visibility"},
            {XamlAttribute::isEnabled, XamlAttributeGroup::layout, "isEnabled"},
            {XamlAttribute::opacity, XamlAttributeGroup::layout, "opacity"},
            {XamlAttribute::itemsSource, XamlAttributeGroup::itemsSource, "itemsSource"},
            {XamlAttribute::renderer, XamlAttributeGroup::renderer, "renderer"},
            {XamlAttribute::verticalScrollBarVisibility, XamlAttributeGroup::scroll, "verticalScrollBarVisibility"},
            {XamlAttribute::horizontalScrollBarVisibility, XamlAttributeGroup::scroll, "horizontalScrollBarVisibility"},
            {XamlAttribute::wireframe, XamlAttributeGroup::wireframe, "wireframe"},
        };

        const AttributeMapping* FindAttribute(XamlAttribute attribute) {
            for (const AttributeMapping& mapping : attributeMappings) {
                if (mapping.attribute == attribute) {
                    return &mapping;
                }
            }

            return nullptr;
        }
    } // namespace details

    std::optional<XamlAttribute> ParseXamlAttribute(std::string_view name) {
        for (const details::AttributeMapping& mapping : details::attributeMappings) {
            if (mapping.name == name) {
                return mapping.attribute;
            }
        }

        return std::nullopt;
    }

    std::string_view XamlAttributeName(XamlAttribute attribute) {
        const details::AttributeMapping* mapping = details::FindAttribute(attribute);
        return mapping == nullptr ? "unknown" : mapping->name;
    }

    XamlAttributeGroup XamlAttributeGroupOf(XamlAttribute attribute) {
        const details::AttributeMapping* mapping = details::FindAttribute(attribute);
        return mapping == nullptr ? XamlAttributeGroup::identity : mapping->group;
    }
}