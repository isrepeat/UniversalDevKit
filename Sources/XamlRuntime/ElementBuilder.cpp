#include "../../Includes/XamlRuntime/UniversalDevKit/XamlRuntime/ElementBuilder.h"
#include "../../Includes/XamlRuntime/UniversalDevKit/XamlRuntime/XamlAttribute.h"

#include <stdexcept>
#include <algorithm>
#include <cstdint>
#include <sstream>
#include <string>
#include <vector>

namespace xaml::_details {
    uint32_t AttributeGroups(ElementType type) {
        const uint32_t common = static_cast<uint32_t>(XamlAttributeGroup::identity)
            | static_cast<uint32_t>(XamlAttributeGroup::dataContext)
            | static_cast<uint32_t>(XamlAttributeGroup::layout)
            | static_cast<uint32_t>(XamlAttributeGroup::size)
            | static_cast<uint32_t>(XamlAttributeGroup::gridPosition)
            | static_cast<uint32_t>(XamlAttributeGroup::renderer)
            | static_cast<uint32_t>(XamlAttributeGroup::wireframe)
            | static_cast<uint32_t>(XamlAttributeGroup::command);
        switch (type) {
        case ElementType::page:
            return common
                | static_cast<uint32_t>(XamlAttributeGroup::background)
                | static_cast<uint32_t>(XamlAttributeGroup::border)
                | static_cast<uint32_t>(XamlAttributeGroup::padding);
        case ElementType::stackPanel:
            return common
                | static_cast<uint32_t>(XamlAttributeGroup::background)
                | static_cast<uint32_t>(XamlAttributeGroup::border)
                | static_cast<uint32_t>(XamlAttributeGroup::padding)
                | static_cast<uint32_t>(XamlAttributeGroup::orientation);
        case ElementType::textBlock:
            return common
                | static_cast<uint32_t>(XamlAttributeGroup::text);
        case ElementType::button:
            return common
                | static_cast<uint32_t>(XamlAttributeGroup::background)
                | static_cast<uint32_t>(XamlAttributeGroup::activeBackground)
                | static_cast<uint32_t>(XamlAttributeGroup::border)
                | static_cast<uint32_t>(XamlAttributeGroup::activeBorder)
                | static_cast<uint32_t>(XamlAttributeGroup::activeForeground)
                | static_cast<uint32_t>(XamlAttributeGroup::padding)
                | static_cast<uint32_t>(XamlAttributeGroup::cornerRadius)
                | static_cast<uint32_t>(XamlAttributeGroup::text)
                | static_cast<uint32_t>(XamlAttributeGroup::contentAlignment)
                | static_cast<uint32_t>(XamlAttributeGroup::command);
        case ElementType::border:
            return common
                | static_cast<uint32_t>(XamlAttributeGroup::background)
                | static_cast<uint32_t>(XamlAttributeGroup::border)
                | static_cast<uint32_t>(XamlAttributeGroup::padding)
                | static_cast<uint32_t>(XamlAttributeGroup::cornerRadius)
                | static_cast<uint32_t>(XamlAttributeGroup::command);
        case ElementType::toggleSwitch:
            return common
                | static_cast<uint32_t>(XamlAttributeGroup::background)
                | static_cast<uint32_t>(XamlAttributeGroup::border)
                | static_cast<uint32_t>(XamlAttributeGroup::text)
                | static_cast<uint32_t>(XamlAttributeGroup::tint)
                | static_cast<uint32_t>(XamlAttributeGroup::toggle)
                | static_cast<uint32_t>(XamlAttributeGroup::command);
        case ElementType::grid:
            return common
                | static_cast<uint32_t>(XamlAttributeGroup::background)
                | static_cast<uint32_t>(XamlAttributeGroup::border)
                | static_cast<uint32_t>(XamlAttributeGroup::padding)
                | static_cast<uint32_t>(XamlAttributeGroup::gridDefinitions);
        case ElementType::scrollViewer:
            return common
                | static_cast<uint32_t>(XamlAttributeGroup::background)
                | static_cast<uint32_t>(XamlAttributeGroup::border)
                | static_cast<uint32_t>(XamlAttributeGroup::padding)
                | static_cast<uint32_t>(XamlAttributeGroup::scroll);
        case ElementType::image:
        case ElementType::svgImage:
            return common
                | static_cast<uint32_t>(XamlAttributeGroup::source)
                | static_cast<uint32_t>(XamlAttributeGroup::tint);
        case ElementType::iconButton:
            return common
                | static_cast<uint32_t>(XamlAttributeGroup::background)
                | static_cast<uint32_t>(XamlAttributeGroup::border)
                | static_cast<uint32_t>(XamlAttributeGroup::padding)
                | static_cast<uint32_t>(XamlAttributeGroup::cornerRadius)
                | static_cast<uint32_t>(XamlAttributeGroup::source)
                | static_cast<uint32_t>(XamlAttributeGroup::tint)
                | static_cast<uint32_t>(XamlAttributeGroup::command);
        case ElementType::listView:
            return common
                | static_cast<uint32_t>(XamlAttributeGroup::background)
                | static_cast<uint32_t>(XamlAttributeGroup::border)
                | static_cast<uint32_t>(XamlAttributeGroup::padding)
                | static_cast<uint32_t>(XamlAttributeGroup::itemsSource);
        }

        return 0;
    }

    bool IsAttributeSupported(ElementType type, XamlAttribute attribute) {
        const uint32_t supportedGroups = AttributeGroups(type);
        const uint32_t attributeGroup = static_cast<uint32_t>(XamlAttributeGroupOf(attribute));
        return (supportedGroups & attributeGroup) != 0;
    }

    bool IsChildSupported(ElementType parent, ElementType child) {
        switch (parent) {
        case ElementType::page:
        case ElementType::stackPanel:
        case ElementType::grid:
        case ElementType::listView:
            return child != ElementType::page;
        case ElementType::border:
        case ElementType::scrollViewer:
        case ElementType::button:
            return child != ElementType::page;
        case ElementType::iconButton:
        case ElementType::textBlock:
        case ElementType::toggleSwitch:
        case ElementType::image:
        case ElementType::svgImage:
            return false;
        }

        return false;
    }

    std::string ElementTypeName(ElementType type) {
        switch (type) {
        case ElementType::page:
            return "Page";
        case ElementType::stackPanel:
            return "StackPanel";
        case ElementType::textBlock:
            return "TextBlock";
        case ElementType::button:
            return "Button";
        case ElementType::border:
            return "Border";
        case ElementType::toggleSwitch:
            return "ToggleSwitch";
        case ElementType::grid:
            return "Grid";
        case ElementType::scrollViewer:
            return "ScrollViewer";
        case ElementType::image:
            return "Image";
        case ElementType::svgImage:
            return "SvgImage";
        case ElementType::iconButton:
            return "IconButton";
        case ElementType::listView:
            return "ListView";
        }

        return "unknown";
    }

    attr::Color ParseColor(std::string_view value) {
        std::string normalized(value);
        if (normalized == "black") {
            normalized = "#000000";
        } else if (normalized == "blue") {
            normalized = "#0000FF";
        } else if (normalized == "gray") {
            normalized = "#808080";
        } else if (normalized == "green") {
            normalized = "#008000";
        } else if (normalized == "red") {
            normalized = "#FF0000";
        } else if (normalized == "white") {
            normalized = "#FFFFFF";
        }
        if ((normalized.size() != 7 && normalized.size() != 9) || normalized.front() != '#') {
            throw std::invalid_argument("color must use #RRGGBB, #AARRGGBB or a supported name");
        }
        if (!std::all_of(normalized.begin() + 1, normalized.end(), [](unsigned char character) {
            return (character >= '0' && character <= '9') || (character >= 'a' && character <= 'f')
                || (character >= 'A' && character <= 'F');
        })) {
            throw std::invalid_argument("color contains invalid hexadecimal digits");
        }
        const unsigned long color = std::stoul(normalized.substr(1), nullptr, 16);
        const unsigned long alpha = normalized.size() == 9 ? (color >> 24) & 0xff : 0xff;
        return {
            static_cast<float>((color >> 16) & 0xff) / 255.0f,
            static_cast<float>((color >> 8) & 0xff) / 255.0f,
            static_cast<float>(color & 0xff) / 255.0f,
            static_cast<float>(alpha) / 255.0f,
        };
    }

    attr::Thickness ParseThickness(std::string_view value) {
        std::string normalized(value);
        std::replace(normalized.begin(), normalized.end(), ',', ' ');
        std::istringstream input(normalized);
        std::vector<float> values;
        float component = 0.0f;
        while (input >> component) {
            values.push_back(component);
        }
        if (values.size() == 1) {
            values = {values[0], values[0], values[0], values[0]};
        }
        if (values.size() != 4) {
            throw std::invalid_argument("thickness must contain left right top bottom");
        }
        return {values[0], values[1], values[2], values[3]};
    }

    attr::Alignment ParseAlignment(std::string_view value) {
        if (value == "Stretch") {
            return attr::Alignment::stretch;
        }
        if (value == "Left") {
            return attr::Alignment::left;
        }
        if (value == "Right") {
            return attr::Alignment::right;
        }
        if (value == "Top") {
            return attr::Alignment::top;
        }
        if (value == "Bottom") {
            return attr::Alignment::bottom;
        }
        if (value == "Center") {
            return attr::Alignment::center;
        }
        throw std::invalid_argument("unsupported alignment");
    }

    bool ParseBool(std::string_view value) {
        if (value == "True" || value == "true") {
            return true;
        }
        if (value == "False" || value == "false") {
            return false;
        }
        throw std::invalid_argument("boolean value must be True or False");
    }

    attr::Wireframe ParseWireframe(std::string_view value) {
        std::istringstream input{std::string(value)};
        float thickness = 0.0f;
        std::string lineStyle;
        std::string color;
        if (!(input >> thickness >> lineStyle >> color) || thickness <= 0.0f) {
            throw std::invalid_argument("wireframe must use '<thickness> <solid|dashed> <color>'");
        }
        if (lineStyle != "solid" && lineStyle != "dashed") {
            throw std::invalid_argument("wireframe line style must be solid or dashed");
        }
        attr::Wireframe wireframe{
            thickness,
            lineStyle == "solid" ? attr::WireframeLineStyle::solid : attr::WireframeLineStyle::dashed,
            ParseColor(color),
        };
        std::string flag;
        while (input >> flag) {
            if (flag.rfind("-m:", 0) == 0 && flag.size() > 3) {
                wireframe.marginColor = ParseColor(flag.substr(3));
            } else if (flag.rfind("-p:", 0) == 0 && flag.size() > 3) {
                wireframe.paddingColor = ParseColor(flag.substr(3));
            } else {
                throw std::invalid_argument("wireframe supports only -m:<color> and -p:<color> flags");
            }
        }
        return wireframe;
    }
}

namespace xaml {
    attr::Color ParseColor(std::string_view value) {
        return _details::ParseColor(value);
    }

    ElementType ParseElementType(std::string_view name) {
        if (name == "Page") {
            return ElementType::page;
        }
        if (name == "StackPanel") {
            return ElementType::stackPanel;
        }
        if (name == "TextBlock") {
            return ElementType::textBlock;
        }
        if (name == "Button") {
            return ElementType::button;
        }
        if (name == "Border") {
            return ElementType::border;
        }
        if (name == "ToggleSwitch") {
            return ElementType::toggleSwitch;
        }
        if (name == "Grid") {
            return ElementType::grid;
        }
        if (name == "ScrollViewer") {
            return ElementType::scrollViewer;
        }
        if (name == "Image") {
            return ElementType::image;
        }
        if (name == "SvgImage") {
            return ElementType::svgImage;
        }
        if (name == "IconButton") {
            return ElementType::iconButton;
        }
        if (name == "ListView") {
            return ElementType::listView;
        }
        throw std::invalid_argument("unsupported XAML element");
    }

    std::vector<std::string_view> SupportedAttributeNames(ElementType type) {
        std::vector<std::string_view> names;
        for (uint32_t index = 0; index < static_cast<uint32_t>(XamlAttribute::count); ++index) {
            const XamlAttribute attribute = static_cast<XamlAttribute>(index);
            if (_details::IsAttributeSupported(type, attribute)) {
                names.push_back(XamlAttributeName(attribute));
            }
        }
        return names;
    }

    void SetAttribute(Element& element, std::string_view name, std::string_view value) {
        const std::optional<XamlAttribute> attribute = ParseXamlAttribute(name);
        if (!attribute.has_value()) {
            throw std::invalid_argument("unsupported XAML attribute '" + std::string(name) + "'");
        }
        if (!_details::IsAttributeSupported(element.Type(), attribute.value())) {
            throw std::invalid_argument(
                "attribute '" + std::string(XamlAttributeName(attribute.value())) + "' is not supported by "
                + _details::ElementTypeName(element.Type()));
        }
        switch (attribute.value()) {
        case XamlAttribute::id:
            element.SetId(std::string(value));
            return;
        case XamlAttribute::dataContext:
            if (value.size() > 10
                && value.substr(0, 9) == "{Binding "
                && value.back() == '}') {
                element.SetDataContext(nullptr);
                return;
            }
            throw std::invalid_argument("DataContext must use a Binding");
        case XamlAttribute::text:
            element.SetText(std::string(value));
            return;
        case XamlAttribute::fontSize:
            element.SetFontSize(std::stof(std::string(value)));
            return;
        case XamlAttribute::lineHeight:
            element.SetLineHeight(std::stof(std::string(value)));
            return;
        case XamlAttribute::fontFamily:
            element.SetFontFamily(std::string(value));
            return;
        case XamlAttribute::textWrapping:
            if (value != "Wrap" && value != "NoWrap") {
                throw std::invalid_argument("textWrapping must be Wrap or NoWrap");
            }
            element.SetTextWrapping(value == "Wrap");
            return;
        case XamlAttribute::fontWeight:
            element.SetFontWeight(std::string(value));
            return;
        case XamlAttribute::source:
            element.SetSource(std::string(value));
            return;
        case XamlAttribute::tint:
            element.SetTint(_details::ParseColor(value));
            return;
        case XamlAttribute::command:
            if (value.size() > 10
                && value.substr(0, 9) == "{Binding "
                && value.back() == '}') {
                element.SetCommand([]() {});
                return;
            }
            throw std::invalid_argument("Command must use a Binding");
        case XamlAttribute::foreground:
            element.SetForeground(_details::ParseColor(value));
            return;
        case XamlAttribute::orientation:
            if (value != "Horizontal" && value != "Vertical") {
                throw std::invalid_argument("orientation must be Horizontal or Vertical");
            }
            element.SetOrientation(value == "Horizontal"
                ? attr::Orientation::horizontal : attr::Orientation::vertical);
            return;
        case XamlAttribute::verticalAlignment:
            element.SetVerticalAlignment(_details::ParseAlignment(value));
            return;
        case XamlAttribute::horizontalAlignment:
            element.SetHorizontalAlignment(_details::ParseAlignment(value));
            return;
        case XamlAttribute::contentAlignment:
            element.SetContentAlignment(_details::ParseAlignment(value));
            return;
        case XamlAttribute::gridRow:
            element.SetGridRow(std::stoi(std::string(value)));
            return;
        case XamlAttribute::gridColumn:
            element.SetGridColumn(std::stoi(std::string(value)));
            return;
        case XamlAttribute::rows:
            element.SetRows(std::string(value));
            return;
        case XamlAttribute::columns:
            element.SetColumns(std::string(value));
            return;
        case XamlAttribute::background:
            element.SetBackground(_details::ParseColor(value));
            return;
        case XamlAttribute::activeBackground:
            element.SetActiveBackground(_details::ParseColor(value));
            return;
        case XamlAttribute::borderBrush:
            element.SetBorderColor(_details::ParseColor(value));
            return;
        case XamlAttribute::activeBorderBrush:
            element.SetActiveBorderColor(_details::ParseColor(value));
            return;
        case XamlAttribute::activeForeground:
            element.SetActiveForeground(_details::ParseColor(value));
            return;
        case XamlAttribute::margin:
            element.SetMargin(_details::ParseThickness(value));
            return;
        case XamlAttribute::padding:
            element.SetPadding(_details::ParseThickness(value));
            return;
        case XamlAttribute::borderThickness:
            element.SetBorderThickness(_details::ParseThickness(value));
            return;
        case XamlAttribute::wireframe:
            element.SetWireframe(_details::ParseWireframe(value));
            return;
        case XamlAttribute::cornerRadius:
            element.SetCornerRadius(std::stof(std::string(value)));
            return;
        case XamlAttribute::width:
            element.SetWidth(std::stof(std::string(value)));
            return;
        case XamlAttribute::height:
            element.SetHeight(std::stof(std::string(value)));
            return;
        case XamlAttribute::isOn:
            element.SetIsOn(_details::ParseBool(value));
            return;
        case XamlAttribute::visibility:
            if (value != "Collapsed" && value != "Hidden" && value != "Visible") {
                throw std::invalid_argument("unsupported visibility");
            }
            element.SetVisibility(value == "Collapsed" ? attr::Visibility::collapsed
                : value == "Hidden" ? attr::Visibility::hidden : attr::Visibility::visible);
            return;
        case XamlAttribute::isEnabled:
            element.SetIsEnabled(_details::ParseBool(value));
            return;
        case XamlAttribute::opacity:
            element.SetOpacity(std::stof(std::string(value)));
            return;
        case XamlAttribute::itemsSource:
            return;
        case XamlAttribute::renderer:
            element.SetRenderer(std::string(value));
            return;
        case XamlAttribute::verticalScrollBarVisibility:
        case XamlAttribute::horizontalScrollBarVisibility: {
            attr::ScrollBarVisibility visibility;
            if (value == "Auto") {
                visibility = attr::ScrollBarVisibility::autoValue;
            } else if (value == "Disabled") {
                visibility = attr::ScrollBarVisibility::disabled;
            } else if (value == "Hidden") {
                visibility = attr::ScrollBarVisibility::hidden;
            } else if (value == "Visible") {
                visibility = attr::ScrollBarVisibility::visible;
            } else {
                throw std::invalid_argument("scroll bar visibility must be Auto, Disabled, Hidden or Visible");
            }
            if (attribute.value() == XamlAttribute::verticalScrollBarVisibility) {
                element.SetVerticalScrollBarVisibility(visibility);
            } else {
                element.SetHorizontalScrollBarVisibility(visibility);
            }
            return;
        }
        }
    }

    void ValidateChild(const Element& parent, const Element& child) {
        if (!_details::IsChildSupported(parent.Type(), child.Type())) {
            throw std::invalid_argument(
                _details::ElementTypeName(parent.Type()) + " cannot contain " + _details::ElementTypeName(child.Type()));
        }
        if ((parent.Type() == ElementType::border || parent.Type() == ElementType::scrollViewer
            || parent.Type() == ElementType::button)
            && !parent.Children().empty()) {
            throw std::invalid_argument(_details::ElementTypeName(parent.Type()) + " can contain only one child");
        }
    }
}