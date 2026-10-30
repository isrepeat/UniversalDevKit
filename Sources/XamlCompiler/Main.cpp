#include <string_view>
#include <filesystem>
#include <algorithm>
#include <stdexcept>
#include <iostream>
#include <sstream>
#include <fstream>
#include <cctype>
#include <string>
#include <vector>
#include <cmath>
#include <regex>
#include <map>
#include <set>

namespace {
    struct Element {
        // Промежуточное дерево: оно не зависит от runtime и существует только
        // во время компиляции XAML в C++.
        std::string name;
        std::vector<std::pair<std::string, std::string>> attributes;
        std::vector<Element> children;
        size_t offset = 0;
    };

    struct Binding {
        std::string elementVariable;
        std::string property;
        std::string source;
        std::string sourceProperty;
        std::string mode;
    };

    struct Style {
        std::string targetType;
        std::vector<std::pair<std::string, std::string>> setters;
    };

    class XamlCompiler {
    public:
        void Compile(
            const std::filesystem::path& input,
            const std::filesystem::path& outputPath,
            const std::vector<std::string>& ignoredDirectories,
            const std::vector<std::string>& ignoredFileSuffixes,
            std::string xamlNamespace,
            std::string controlXmlPrefix,
            std::string controlCppNamespace,
            std::string controlIncludePrefix);

    private:
        std::map<std::string, Style> styles;
        std::set<std::string> requiredControls;
        const std::string* xamlSource = nullptr;
        std::string xamlSourcePath;
        std::string xamlNamespace;
        std::string controlXmlPrefix;
        std::string controlCppNamespace;

        bool IsIgnored(
            const std::filesystem::path& input,
            const std::vector<std::string>& ignoredDirectories,
            const std::vector<std::string>& ignoredFileSuffixes) {
            for (const std::filesystem::path& component : input.lexically_normal()) {
                for (const std::string& directory : ignoredDirectories) {
                    if (component == directory) {
                        return true;
                    }
                }
            }
            const std::string fileName = input.stem().string();
            for (const std::string& suffix : ignoredFileSuffixes) {
                if (fileName.size() >= suffix.size()
                    && fileName.compare(fileName.size() - suffix.size(), suffix.size(), suffix) == 0) {
                    return true;
                }
            }
            return false;
        }

        std::string UserControlName(const Element& element) {
            const std::string prefix = this->controlXmlPrefix + ":";
            if (element.name.rfind(prefix, 0) != 0) {
                return {};
            }
            const std::string name = element.name.substr(prefix.size());
            if (!std::regex_match(name, std::regex(R"([A-Za-z][A-Za-z0-9]*)"))) {
                throw std::runtime_error("UserControl name must be a valid C++ type name");
            }
            return name;
        }

        std::string ReadFile(const std::filesystem::path& path) {
            std::ifstream input(path, std::ios::binary);
            if (!input) {
                throw std::runtime_error("Cannot read " + path.string());
            }
            return {
                std::istreambuf_iterator<char>(input),
                std::istreambuf_iterator<char>(),
            };
        }

        std::string EscapeCpp(const std::string& value) {
            std::string result;
            for (const char character : value) {
                if (character == '\\' || character == '"') {
                    result += '\\';
                }
                result += character;
            }
            return result;
        }

        size_t LineNumber(const std::string& source, size_t offset) {
            return 1 + static_cast<size_t>(
                std::count(source.begin(), source.begin() + offset, '\n'));
        }

        size_t ColumnNumber(const std::string& source, size_t offset) {
            const size_t lineStart = source.rfind('\n', offset);
            return offset - (lineStart == std::string::npos ? 0 : lineStart + 1) + 1;
        }

        [[noreturn]] void Fail(
            const std::filesystem::path& path,
            const std::string& source,
            size_t offset,
            const std::string& message) {
            throw std::runtime_error(
                path.string() + ":" + std::to_string(this->LineNumber(source, offset))
                + ": " + message);
        }

        void AppendElement(
            Element element,
            std::vector<Element>& stack,
            Element& root,
            bool& hasRoot,
            const std::filesystem::path& path,
            const std::string& source,
            size_t offset) {
            // Верхушка stack — родитель текущего закрытого/self-closing элемента.
            // Пустой stack означает, что element является корнем документа.
            if (!stack.empty()) {
                stack.back().children.push_back(std::move(element));
                return;
            }
            if (hasRoot) {
                this->Fail(path, source, offset, "only one root element is allowed");
            }
            root = std::move(element);
            hasRoot = true;
        }

        Element Parse(const std::filesystem::path& path, const std::string& source) {
            // Это намеренно небольшой XAML-диалект, а не универсальный XML-парсер:
            // он принимает только теги/атрибуты, которые способен выразить runtime.
            const std::regex tagPattern(R"(<\s*([^>]+)>)");
            const std::regex attributePattern(
                R"attr(([A-Za-z][A-Za-z0-9:]*)\s*=\s*"([^"]*)")attr");
            const std::regex namePattern(R"(^\s*([A-Za-z][A-Za-z0-9.:]*))");
            std::vector<Element> stack;
            Element root;
            bool hasRoot = false;
            std::sregex_iterator end;

            for (std::sregex_iterator tag(source.begin(), source.end(), tagPattern);
                tag != end;
                ++tag) {
                const auto& match = *tag;
                const size_t offset = static_cast<size_t>(match.position());
                const std::string content = match[1].str();
                if (content.rfind("!--", 0) == 0 || content.rfind("?", 0) == 0) {
                    continue;
                }

                const bool closing = !content.empty() && content.front() == '/';
                const bool selfClosing = !closing && !content.empty()
                    && content.back() == '/';
                if (closing) {
                    // Закрывающий тег завершает элемент и присоединяет его к
                    // родителю. Так стек сохраняет вложенность без рекурсии.
                    const std::string name = std::regex_replace(
                        content.substr(1), std::regex(R"(\s+)"), "");
                    if (stack.empty() || stack.back().name != name) {
                        this->Fail(path, source, offset, "unexpected closing tag </" + name + ">");
                    }
                    Element element = std::move(stack.back());
                    stack.pop_back();
                    this->AppendElement(std::move(element), stack, root, hasRoot, path, source, offset);
                    continue;
                }

                std::smatch nameMatch;
                std::regex_search(content, nameMatch, namePattern);
                if (nameMatch.empty()) {
                    this->Fail(path, source, offset, "element name is required");
                }
                Element element{nameMatch[1].str(), {}, {}, offset};
                for (std::sregex_iterator attribute(
                    content.begin(), content.end(), attributePattern);
                    attribute != end;
                    ++attribute) {
                    element.attributes.emplace_back((*attribute)[1].str(), (*attribute)[2].str());
                }
                if (selfClosing) {
                    this->AppendElement(std::move(element), stack, root, hasRoot, path, source, offset);
                } else {
                    stack.push_back(std::move(element));
                }
            }

            if (!stack.empty()) {
                this->Fail(path, source, stack.back().offset, "element is not closed");
            }
            if (!hasRoot) {
                this->Fail(path, source, 0, "root element is required");
            }
            return root;
        }

        std::string ElementTypeName(const Element& element) {
            if (element.name == "Page") {
                return "page";
            }
            if (element.name == "StackPanel") {
                return "stackPanel";
            }
            if (element.name == "TextBlock") {
                return "textBlock";
            }
            if (element.name == "Button") {
                return "button";
            }
            if (element.name == "Border") {
                return "border";
            }
            if (element.name == "ToggleSwitch") {
                return "toggleSwitch";
            }
            if (element.name == "Grid") {
                return "grid";
            }
            if (element.name == "ScrollViewer") {
                return "scrollViewer";
            }
            if (element.name == "Image") {
                return "image";
            }
            if (element.name == "SvgImage") {
                return "svgImage";
            }
            if (element.name == "IconButton") {
                return "iconButton";
            }
            if (element.name == "ListView") {
                return "listView";
            }
            throw std::runtime_error("Unsupported XAML element <" + element.name + ">");
        }

        std::string FloatLiteral(const std::string& value) {
            return std::to_string(std::stof(value)) + "f";
        }

        std::string ThicknessLiteral(const std::string& value) {
            std::string normalized = value;
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
                throw std::runtime_error("Thickness must contain one or four values: left right top bottom");
            }
            return "attr::Thickness{" + std::to_string(values[0]) + "f, " + std::to_string(values[1])
                + "f, " + std::to_string(values[2]) + "f, " + std::to_string(values[3]) + "f}";
        }

        std::string WireframeLiteral(const std::string& value) {
            std::istringstream input(value);
            float thickness = 0.0f;
            std::string lineStyle;
            std::string color;
            if (!(input >> thickness >> lineStyle >> color) || thickness <= 0.0f) {
                throw std::runtime_error("wireframe must use '<thickness> <solid|dashed> <color>'");
            }
            if (lineStyle != "solid" && lineStyle != "dashed") {
                throw std::runtime_error("wireframe line style must be solid or dashed");
            }
            std::string marginColor{"{0.0f, 0.0f, 0.0f, 0.0f}"};
            std::string paddingColor{"{0.0f, 0.0f, 0.0f, 0.0f}"};
            std::string flag;
            while (input >> flag) {
                if (flag.rfind("-m:", 0) == 0 && flag.size() > 3) {
                    marginColor = this->ColorLiteral("wireframe margin", flag.substr(3));
                } else if (flag.rfind("-p:", 0) == 0 && flag.size() > 3) {
                    paddingColor = this->ColorLiteral("wireframe padding", flag.substr(3));
                } else {
                    throw std::runtime_error("wireframe supports only -m:<color> and -p:<color> flags");
                }
            }
            return "{" + std::to_string(thickness) + "f, attr::WireframeLineStyle::" + lineStyle
                + ", " + this->ColorLiteral("wireframe", color) + ", " + marginColor + ", " + paddingColor + "}";
        }

        std::string ColorLiteral(const std::string& name, const std::string& value) {
            const std::map<std::string, std::string> namedColors{
                {"black", "#000000"},
                {"blue", "#0000FF"},
                {"gray", "#808080"},
                {"green", "#008000"},
                {"red", "#FF0000"},
                {"white", "#FFFFFF"},
            };
            const auto namedColor = namedColors.find(value);
            const std::string normalized = namedColor == namedColors.end() ? value : namedColor->second;
            if ((normalized.size() != 7 && normalized.size() != 9) || normalized.front() != '#') {
                throw std::runtime_error(name + " must use #RRGGBB, #AARRGGBB or a supported color name");
            }
            if (!std::all_of(normalized.begin() + 1, normalized.end(), [](unsigned char character) {
                return (character >= '0' && character <= '9') || (character >= 'a' && character <= 'f')
                    || (character >= 'A' && character <= 'F');
            })) {
                throw std::runtime_error(name + " contains invalid hexadecimal digits");
            }
            const unsigned long color = std::stoul(normalized.substr(1), nullptr, 16);
            const unsigned long alpha = normalized.size() == 9 ? (color >> 24) & 0xff : 0xff;
            return "attr::Color{" + std::to_string((color >> 16) & 0xff) + ".0f / 255.0f, "
                + std::to_string((color >> 8) & 0xff) + ".0f / 255.0f, "
                + std::to_string(color & 0xff) + ".0f / 255.0f, "
                + std::to_string(alpha) + ".0f / 255.0f}";
        }

        std::string AttributeValue(const Element& element, const std::string& name) {
            const auto attribute = std::find_if(
                element.attributes.begin(),
                element.attributes.end(),
                [&name](const auto& value) { return value.first == name; });
            return attribute == element.attributes.end() ? std::string{} : attribute->second;
        }

        bool UsesControlItemsSource(const Element& element) {
            if (element.name == "ListView"
                && this->AttributeValue(element, "itemsSource") == "{Binding ItemsSource}") {
                return true;
            }
            return std::any_of(
                element.children.begin(),
                element.children.end(),
                [this](const Element& child) { return this->UsesControlItemsSource(child); });
        }

        std::string PropertyName(const std::string& name) {
            if (name.empty()) {
                return name;
            }
            std::string result = name;
            result.front() = static_cast<char>(std::tolower(result.front()));
            return result;
        }

        void AddStyle(const Element& element) {
            if (element.name != "Style") {
                throw std::runtime_error("Only <Style> is allowed inside <Page.Resources>");
            }
            const std::string key = this->AttributeValue(element, "x:Key");
            const std::string targetType = this->AttributeValue(element, "TargetType");
            if (key.empty() || targetType.empty()) {
                throw std::runtime_error("<Style> requires x:Key and TargetType");
            }
            Style style{targetType, {}};
            for (const Element& setter : element.children) {
                if (setter.name != "Setter" || !setter.children.empty()) {
                    throw std::runtime_error("Only empty <Setter> is allowed inside <Style>");
                }
                const std::string property = this->AttributeValue(setter, "Property");
                const std::string value = this->AttributeValue(setter, "Value");
                if (property.empty() || value.empty()) {
                    throw std::runtime_error("<Setter> requires Property and Value");
                }
                style.setters.emplace_back(this->PropertyName(property), value);
            }
            if (!this->styles.emplace(key, std::move(style)).second) {
                throw std::runtime_error("Duplicate resource key: " + key);
            }
        }

        void LoadResources(const Element& page) {
            this->styles.clear();
            for (const Element& child : page.children) {
                if (child.name != page.name + ".Resources") {
                    continue;
                }
                for (const Element& resource : child.children) {
                    if (resource.name == "ResourceDictionary") {
                        for (const Element& entry : resource.children) {
                            this->AddStyle(entry);
                        }
                    } else {
                        this->AddStyle(resource);
                    }
                }
            }
        }

        const Style& FindStyle(const Element& element) {
            const std::string reference = this->AttributeValue(element, "style");
            const std::regex pattern(R"(^\{StaticResource\s+([A-Za-z][A-Za-z0-9]*)\}$)");
            std::smatch match;
            if (!std::regex_match(reference, match, pattern)) {
                throw std::runtime_error("style must use {StaticResource Key}");
            }
            const auto style = this->styles.find(match[1].str());
            if (style == this->styles.end()) {
                throw std::runtime_error("Resource not found: " + match[1].str());
            }
            if (style->second.targetType != element.name) {
                throw std::runtime_error("Style target type does not match <" + element.name + ">");
            }
            return style->second;
        }

        bool TryEmitBinding(
            const std::string& elementVariable,
            const std::string& name,
            const std::string& value,
            std::vector<Binding>& bindings,
            const std::string& source) {
            const std::regex bindingPattern(
                R"(^\{Binding\s+([A-Za-z][A-Za-z0-9]*)(?:\s*,\s*Mode\s*=\s*(OneWay|TwoWay))?\s*\}$)");
            std::smatch match;
            if (!std::regex_match(value, match, bindingPattern)) {
                return false;
            }
            bindings.push_back({
                elementVariable,
                name,
                source,
                match[1].str(),
                match[2].matched && match[2].str() == "TwoWay" ? "twoWay" : "oneWay",
            });
            return true;
        }

        bool TryGetBindingSource(const std::string& value, std::string& sourceProperty) {
            const std::regex bindingPattern(R"(^\{Binding\s+([A-Za-z][A-Za-z0-9]*)\s*\}$)");
            std::smatch match;
            if (!std::regex_match(value, match, bindingPattern)) {
                return false;
            }
            sourceProperty = match[1].str();
            return true;
        }

        void EmitProperty(
            const Element& element,
            const std::string& variable,
            const std::string& name,
            const std::string& value,
            std::ostringstream& output,
            const std::string& elementVariable,
            std::vector<Binding>& bindings,
            const std::string& templateItem,
            const std::string& bindingContext) {
            // Атрибуты переводятся в явные вызовы setter'ов. Поэтому итоговый код
            // не разбирает строки в рантайме и остаётся обычным C++.
            if (name == "itemsSource" && element.name == "ListView") {
                return;
            }
            std::string templateProperty;
            if (!templateItem.empty() && bindingContext == templateItem
                && this->TryGetBindingSource(value, templateProperty)) {
                if (name == "text") {
                    output << "            " << variable << "->SetText(" << templateItem
                        << "." << templateProperty << "());\n";
                    return;
                }
                if (name == "isOn") {
                    output << "            " << variable << "->SetIsOn(" << templateItem
                        << "." << templateProperty << "());\n";
                    return;
                }
                if (name == "command") {
                    output << "            " << variable << "->SetCommand(" << templateItem
                        << "." << templateProperty << "());\n";
                    return;
                }
                throw std::runtime_error("Unsupported ItemTemplate binding target: " + name);
            }
            if (this->TryEmitBinding(elementVariable, name, value, bindings, bindingContext)) {
                return;
            }
            if (name == "id") {
                output << "            " << variable << "->SetId(\"" << this->EscapeCpp(value) << "\");\n";
            } else if (name == "text") {
                output << "            " << variable << "->SetText(\"" << this->EscapeCpp(value) << "\");\n";
            } else if (name == "fontSize") {
                output << "            " << variable << "->SetFontSize(" << this->FloatLiteral(value) << ");\n";
            } else if (name == "lineHeight") {
                output << "            " << variable << "->SetLineHeight(" << this->FloatLiteral(value) << ");\n";
            } else if (name == "fontFamily") {
                output << "            " << variable << "->SetFontFamily(\"" << this->EscapeCpp(value) << "\");\n";
            } else if (name == "fontWeight") {
                output << "            " << variable << "->SetFontWeight(\"" << this->EscapeCpp(value) << "\");\n";
            } else if (name == "textWrapping") {
                if (value != "Wrap" && value != "NoWrap") {
                    throw std::runtime_error("TextWrapping must be Wrap or NoWrap");
                }
                output << "            " << variable << "->SetTextWrapping("
                    << (value == "Wrap" ? "true" : "false") << ");\n";
            } else if (name == "source") {
                output << "            " << variable << "->SetSource(\"" << this->EscapeCpp(value) << "\");\n";
            } else if (name == "command") {
                throw std::runtime_error("Command must use a Binding");
            } else if (name == "gridRow" || name == "gridColumn") {
                output << "            " << variable << "->Set" << (name == "gridRow" ? "GridRow" : "GridColumn")
                    << "(" << std::stoi(value) << ");\n";
            } else if (name == "opacity") {
                output << "            " << variable << "->SetOpacity(" << this->FloatLiteral(value) << ");\n";
            } else if (name == "visibility") {
                const std::string visibility = value == "Collapsed" ? "collapsed"
                    : value == "Hidden" ? "hidden"
                    : (value == "Vissible" || value == "Visible") ? "visible" : "";
                if (visibility.empty()) {
                    throw std::runtime_error("Visibility must be Collapsed, Hidden or Vissible");
                }
                output << "            " << variable << "->SetVisibility(attr::Visibility::"
                    << visibility << ");\n";
            } else if (name == "isEnabled") {
                if (value != "True" && value != "False") {
                    throw std::runtime_error("IsEnabled must be True or False");
                }
                output << "            " << variable << "->SetIsEnabled(" << (value == "True" ? "true" : "false") << ");\n";
            } else if (name == "margin" || name == "padding") {
                output << "            " << variable << "->Set" << (name == "margin" ? "Margin" : "Padding")
                    << "(" << this->ThicknessLiteral(value) << ");\n";
            } else if (name == "borderThickness") {
                output << "            " << variable << "->SetBorderThickness(" << this->ThicknessLiteral(value) << ");\n";
            } else if (name == "wireframe") {
                output << "            " << variable << "->SetWireframe(" << this->WireframeLiteral(value) << ");\n";
            } else if (name == "borderBrush") {
                output << "            " << variable << "->SetBorderColor("
                    << this->ColorLiteral(name, value) << ");\n";
            } else if (name == "cornerRadius") {
                output << "            " << variable << "->SetCornerRadius(" << this->FloatLiteral(value) << ");\n";
            } else if (name == "width") {
                output << "            " << variable << "->SetWidth(" << this->FloatLiteral(value) << ");\n";
            } else if (name == "height") {
                output << "            " << variable << "->SetHeight(" << this->FloatLiteral(value) << ");\n";
            } else if (name == "isOn") {
                if (value != "True" && value != "False") {
                    throw std::runtime_error("IsOn must be True or False");
                }
                output << "            " << variable << "->SetIsOn(" << (value == "True" ? "true" : "false") << ");\n";
            } else if (name == "orientation") {
                const std::string orientation = value == "Horizontal" ? "horizontal"
                    : value == "Vertical" ? "vertical" : "";
                if (orientation.empty()) {
                    throw std::runtime_error("Orientation must be Horizontal or Vertical");
                }
                output << "            " << variable << "->SetOrientation(attr::Orientation::"
                    << orientation << ");\n";
            } else if (name == "verticalScrollBarVisibility" || name == "horizontalScrollBarVisibility") {
                const std::string visibility = value == "Auto" ? "autoValue"
                    : value == "Disabled" ? "disabled"
                    : value == "Hidden" ? "hidden"
                    : value == "Visible" ? "visible" : "";
                if (visibility.empty()) {
                    throw std::runtime_error("ScrollBarVisibility must be Auto, Disabled, Hidden or Visible");
                }
                const std::string setter = name == "verticalScrollBarVisibility"
                    ? "VerticalScrollBarVisibility" : "HorizontalScrollBarVisibility";
                output << "            " << variable << "->Set" << setter
                    << "(attr::ScrollBarVisibility::" << visibility << ");\n";
            } else if (name == "verticalAlignment") {
                if (value == "Top") {
                    output << "            " << variable << "->SetVerticalAlignment(attr::Alignment::top);\n";
                } else if (value == "Bottom") {
                    output << "            " << variable << "->SetVerticalAlignment(attr::Alignment::bottom);\n";
                } else if (value == "Stretch") {
                    output << "            " << variable << "->SetVerticalAlignment(attr::Alignment::stretch);\n";
                } else if (value != "Center") {
                    throw std::runtime_error("VerticalAlignment must be Top, Center, Bottom or Stretch");
                }
            } else if (name == "horizontalAlignment" || name == "contentAlignment") {
                const std::string alignment = value == "Left" ? "left"
                    : value == "Right" ? "right" : value == "Center" ? "center"
                    : value == "Stretch" ? "stretch" : "";
                if (alignment.empty()) {
                    throw std::runtime_error(name + " must be Left, Center, Right or Stretch");
                }
                const std::string setter = name == "horizontalAlignment"
                    ? "HorizontalAlignment" : "ContentAlignment";
                output << "            " << variable << "->Set" << setter << "(attr::Alignment::"
                    << alignment << ");\n";
            } else if (name == "foreground" || name == "background") {
                const std::string setter = name == "foreground" ? "Foreground"
                    : "Background";
                output << "            " << variable << "->Set" << setter << "(" << this->ColorLiteral(name, value) << ");\n";
            } else if (name == "tint") {
                output << "            " << variable << "->SetTint(" << this->ColorLiteral(name, value) << ");\n";
            } else {
                throw std::runtime_error(
                    "Unsupported attribute " + name + " on <" + element.name + ">");
            }
        }

        std::string ElementVariableName(
            const Element& element,
            std::map<std::string, size_t>& elementCounts) {
            const std::string userControlName = this->UserControlName(element);
            std::string result = userControlName.empty() ? element.name : userControlName;
            result.front() = static_cast<char>(result.front() - 'A' + 'a');
            if (element.name == "Page") {
                return result;
            }
            return result + std::to_string(++elementCounts[element.name]);
        }

        std::string EmitElement(
            const Element& element,
            std::ostringstream& output,
            std::map<std::string, size_t>& elementCounts,
            const std::string& templateItem = "",
            const std::string& bindingContext = "viewModel") {
            const std::string userControlName = this->UserControlName(element);
            if (!userControlName.empty()) {
                if (!element.children.empty()) {
                    throw std::runtime_error("<" + element.name + "> cannot contain child elements");
                }
                this->requiredControls.emplace(userControlName);
                const std::string variable = this->ElementVariableName(element, elementCounts);
                std::string childBindingContext = bindingContext;
                const std::string dataContext = this->AttributeValue(element, "dataContext");
                if (!dataContext.empty()) {
                    std::string sourceProperty;
                    if (!this->TryGetBindingSource(dataContext, sourceProperty)) {
                        throw std::runtime_error("DataContext must use {Binding Property}");
                    }
                    childBindingContext += "." + sourceProperty + "()";
                }
                const std::string itemsSource = this->AttributeValue(element, "itemsSource");
                std::string itemsSourceProperty;
                if (!itemsSource.empty()
                    && !this->TryGetBindingSource(itemsSource, itemsSourceProperty)) {
                    throw std::runtime_error("UserControl itemsSource must use {Binding Property}");
                }
                if (this->controlCppNamespace.empty()) {
                    throw std::runtime_error("Custom control requires --control-cpp-namespace");
                }
                output << "            auto " << variable << " = " << this->controlCppNamespace << "::" << userControlName
                    << "::Create(" << childBindingContext;
                if (!itemsSourceProperty.empty()) {
                    output << ", " << bindingContext << "." << itemsSourceProperty << "()";
                }
                output << ", bindings);\n";
                output << "            " << variable << "->SetSourceLocation("
                    << "\"" << this->EscapeCpp(this->xamlSourcePath) << "\", "
                    << this->LineNumber(*this->xamlSource, element.offset) << ", "
                    << this->ColumnNumber(*this->xamlSource, element.offset) << ");\n";
                std::vector<Binding> bindings;
                for (const auto& [name, value] : element.attributes) {
                    if (name.rfind("xmlns", 0) == 0 || name == "dataContext" || name == "itemsSource") {
                        continue;
                    }
                    this->EmitProperty(element, variable, name, value, output, variable, bindings, templateItem, bindingContext);
                }
                this->EmitBindings(bindings, output);
                return variable;
            }

            // Сначала объявляем дочерние unique_ptr, затем передаём их родителю.
            // Это повторяет ownership-структуру исходной XAML-разметки.
            const std::string variable = this->ElementVariableName(element, elementCounts);
            std::vector<Binding> bindings;
            output << "            auto " << variable << " = std::make_unique<Element>(ElementType::"
                << this->ElementTypeName(element) << ");\n";
            output << "            " << variable << "->SetSourceLocation("
                << "\"" << this->EscapeCpp(this->xamlSourcePath) << "\", "
                << this->LineNumber(*this->xamlSource, element.offset) << ", "
                << this->ColumnNumber(*this->xamlSource, element.offset) << ");\n";
            std::string childBindingContext = bindingContext;
            const std::string dataContext = this->AttributeValue(element, "dataContext");
            if (!dataContext.empty()) {
                std::string sourceProperty;
                if (!this->TryGetBindingSource(dataContext, sourceProperty)) {
                    throw std::runtime_error("DataContext must use {Binding Property}");
                }
                childBindingContext += "." + sourceProperty + "()";
                output << "            " << variable << "->SetDataContext(static_cast<const void*>(&"
                    << childBindingContext << "));\n";
            }
            if (!this->AttributeValue(element, "style").empty()) {
                for (const auto& [name, value] : this->FindStyle(element).setters) {
                    this->EmitProperty(element, variable, name, value, output, variable, bindings, templateItem, bindingContext);
                }
            }
            for (const auto& [name, value] : element.attributes) {
            if (name.rfind("xmlns", 0) == 0 || name == "style" || name == "dataContext") {
                continue;
            }
            if (name == "animation") {
                throw std::runtime_error("Use <Animation> inside an event <Storyboard>");
            }
            if (name == "renderer") {
                output << "            " << variable << "->SetRenderer(\"" << value << "\");\n";
                continue;
            }
            this->EmitProperty(element, variable, name, value, output, variable, bindings, templateItem, bindingContext);
            }
            if (element.name == "Grid") {
                this->EmitGridDefinitions(element, variable, output);
            }
            this->EmitStoryboards(element, variable, output);
            this->EmitVisualStateGroups(element, variable, output);
            this->EmitBindings(bindings, output);
            if (element.name == "ListView") {
                this->EmitListViewItems(element, variable, output, elementCounts, bindingContext);
                return variable;
            }
            for (size_t childIndex = 0; childIndex < element.children.size(); ++childIndex) {
                if (element.children[childIndex].name == "columnDefinitions"
                    || element.children[childIndex].name == "rowDefinitions"
                    || element.children[childIndex].name == element.name + ".Resources"
                    || element.children[childIndex].name == element.name + ".Storyboards"
                    || element.children[childIndex].name == "VisualStateManager.VisualStateGroups") {
                    continue;
                }
                const std::string childVariable = this->EmitElement(
                    element.children[childIndex], output, elementCounts, templateItem, childBindingContext);
                output << "            " << variable << "->AddChild(std::move(" << childVariable << "));\n";
            }
            return variable;
        }

        void EmitVisualStateGroups(
            const Element& element,
            const std::string& variable,
            std::ostringstream& output) {
            for (const Element& collection : element.children) {
                if (collection.name != "VisualStateManager.VisualStateGroups") {
                    continue;
                }
                output << "            " << variable << "->SetVisualStateGroups({";
                for (size_t groupIndex = 0; groupIndex < collection.children.size(); ++groupIndex) {
                    const Element& group = collection.children[groupIndex];
                    if (group.name != "VisualStateGroup") {
                        throw std::runtime_error("Only <VisualStateGroup> is allowed inside <VisualStateManager.VisualStateGroups>");
                    }
                    const std::string groupName = this->AttributeValue(group, "name");
                    if (groupName.empty()) {
                        throw std::runtime_error("<VisualStateGroup> requires name");
                    }
                    if (groupIndex != 0) {
                        output << ", ";
                    }
                    output << "{\"" << this->EscapeCpp(groupName) << "\", \"\", {";
                    for (size_t stateIndex = 0; stateIndex < group.children.size(); ++stateIndex) {
                        const Element& state = group.children[stateIndex];
                        const std::string stateName = this->AttributeValue(state, "name");
                        if (state.name != "VisualState" || stateName.empty()) {
                            throw std::runtime_error("<VisualState> requires name");
                        }
                        if (stateIndex != 0) {
                            output << ", ";
                        }
                        output << "{\"" << this->EscapeCpp(stateName) << "\", {";
                        const Element* storyboard = nullptr;
                        const Element* setters = nullptr;
                        for (const Element& child : state.children) {
                            if (child.name == "Storyboard") {
                                if (storyboard != nullptr) {
                                    throw std::runtime_error("<VisualState> supports one <Storyboard>");
                                }
                                storyboard = &child;
                            } else if (child.name == "Setters") {
                                if (setters != nullptr) {
                                    throw std::runtime_error("<VisualState> supports one <Setters>");
                                }
                                setters = &child;
                            } else {
                                throw std::runtime_error("<VisualState> supports only <Setters> and <Storyboard>");
                            }
                        }
                        if (storyboard == nullptr) {
                            throw std::runtime_error("<VisualState> requires one <Storyboard>");
                        }
                        for (size_t trackIndex = 0; trackIndex < storyboard->children.size(); ++trackIndex) {
                            const Element& track = storyboard->children[trackIndex];
                            const std::string targetName = this->AttributeValue(track, "targetName");
                            const std::string animationName = track.name == "Animation"
                                ? this->AttributeValue(track, "name") : "";
                            if (!track.children.empty() || targetName.empty()
                                || (track.name != "Animation" && track.name != "FloatAnimation" && track.name != "ColorAnimation")
                                || (track.name == "Animation" && animationName.empty())) {
                                throw std::runtime_error("Visual state Animation requires targetName and name");
                            }
                            if (trackIndex != 0) {
                                output << ", ";
                            }
                            if (track.name == "ColorAnimation") {
                                output << "{\"" << this->EscapeCpp(targetName) << "\", ";
                                this->EmitColorTrack(track, output);
                                output << "}";
                                continue;
                            }
                            if (track.name == "Animation") {
                                output << "{\"" << this->EscapeCpp(targetName) << "\", [] { AnimationTrack track; track.name = \""
                                    << this->EscapeCpp(animationName) << "\";";
                                for (const auto& [key, value] : track.attributes) {
                                    if (key != "name" && key != "targetName") {
                                        output << " track.settings.Set(\"" << this->EscapeCpp(key)
                                            << "\", \"" << this->EscapeCpp(value) << "\");";
                                    }
                                }
                                output << " return track; }()}";
                                continue;
                            }
                            const std::string property = track.name == "FloatAnimation"
                                ? this->AttributeValue(track, "property") : "";
                            const std::string from = this->AttributeValue(track, "from");
                            const std::string to = this->AttributeValue(track, "to");
                            const std::string duration = this->AttributeValue(track, "duration");
                            const std::string easing = this->AttributeValue(track, "easing");
                            if ((property != "opacity" && property != "renderOffsetX" && property != "renderOffsetY"
                                    && property != "height" && property != "toggleProgress" && property != "pressProgress")
                                || from.empty() || to.empty() || duration.empty()) {
                                throw std::runtime_error("Visual state FloatAnimation requires targetName, supported property, from, to and duration");
                            }
                            const std::string easingName = easing.empty() || easing == "CubicOut" ? "cubicOut"
                                : easing == "Linear" ? "linear" : "";
                            if (easingName.empty()) {
                                throw std::runtime_error("Visual state animation easing must be Linear or CubicOut");
                            }
                            const bool fromCurrent = from == "Current";
                            output << "{\"" << this->EscapeCpp(targetName) << "\", {AnimatedProperty::" << property
                                << ", " << (fromCurrent ? "0.0f" : this->FloatLiteral(from)) << ", " << this->FloatLiteral(to)
                                << ", " << (fromCurrent ? "true" : "false") << ", false, std::chrono::milliseconds(" << std::stoi(duration)
                                << "), Easing::" << easingName << "}}";
                        }
                        output << "}, {";
                        if (setters != nullptr) {
                            for (size_t setterIndex = 0; setterIndex < setters->children.size(); ++setterIndex) {
                                const Element& setter = setters->children[setterIndex];
                                const std::string targetName = this->AttributeValue(setter, "targetName");
                                const std::string property = this->AttributeValue(setter, "property");
                                const std::string value = this->AttributeValue(setter, "value");
                                if (setter.name != "Setter" || !setter.children.empty()
                                    || targetName.empty() || value.empty()
                                    || (property != "width" && property != "height"
                                        && property != "horizontalAlignment" && property != "verticalAlignment"
                                        && property != "background")
                                    || (property == "height" && value == "Auto")) {
                                    throw std::runtime_error("Visual state Setter requires supported property, targetName and value");
                                }
                                if (setterIndex != 0) {
                                    output << ", ";
                                }
                                output << "{\"" << this->EscapeCpp(targetName) << "\", \""
                                    << this->EscapeCpp(property) << "\", \"" << this->EscapeCpp(value) << "\"}";
                            }
                        }
                        output << "}}";
                    }
                    output << "}}";
                }
                output << "});\n";
            }
        }

        void EmitColorTrack(const Element& track, std::ostringstream& output) {
            const auto property = this->AttributeValue(track, "property");
            const auto from = this->AttributeValue(track, "from");
            const auto to = this->AttributeValue(track, "to");
            const auto duration = this->AttributeValue(track, "duration");
            const auto easing = this->AttributeValue(track, "easing");
            if (!track.children.empty() || (property != "background" && property != "foreground"
                    && property != "borderBrush" && property != "tint")
                || from.empty() || to.empty() || duration.empty()) {
                throw std::runtime_error("ColorAnimation requires supported property, from, to and duration");
            }
            size_t consumed = 0;
            const float milliseconds = std::stof(duration, &consumed);
            if (consumed != duration.size() || !std::isfinite(milliseconds) || milliseconds < 0 || milliseconds > 86400000) {
                throw std::runtime_error("ColorAnimation duration is out of range");
            }
            const std::string easingName = easing.empty() || easing == "Linear" ? "linear"
                : easing == "CubicOut" ? "cubicOut" : "";
            if (easingName.empty()) {
                throw std::runtime_error("ColorAnimation easing must be Linear or CubicOut");
            }
            output << "AnimationTrack::Color(AnimatedProperty::" << (property == "borderBrush" ? "borderColor" : property)
                << ", " << (from == "Current" ? "attr::Color{}" : this->ColorLiteral("from", from))
                << ", " << this->ColorLiteral("to", to) << ", std::chrono::milliseconds("
                << static_cast<long long>(milliseconds) << "), Easing::" << easingName
                << ", " << (from == "Current" ? "true" : "false") << ")";
        }

        void EmitStoryboards(
            const Element& element,
            const std::string& variable,
            std::ostringstream& output) {
            const std::string collectionName = element.name + ".Storyboards";
            for (const Element& collection : element.children) {
                if (collection.name != collectionName) {
                    continue;
                }

                for (const Element& storyboard : collection.children) {
                    if (storyboard.name != "Storyboard") {
                        throw std::runtime_error("Only <Storyboard> is allowed inside <" + collectionName + ">");
                    }
                    const auto trigger = std::find_if(
                        storyboard.attributes.begin(), storyboard.attributes.end(),
                        [](const auto& attribute) { return attribute.first == "trigger"; });
                    if (trigger == storyboard.attributes.end()) {
                        throw std::runtime_error("<Storyboard> requires trigger");
                    }
                    const std::string triggerName = trigger->second == "PointerDown" ? "pointerDown"
                        : trigger->second == "PointerUp" ? "pointerUp"
                        : trigger->second == "Toggled" ? "toggled"
                        : trigger->second == "Show" ? "show"
                        : trigger->second == "Hide" ? "hide"
                        : trigger->second == "ParentShow" ? "parentShow"
                        : trigger->second == "ParentHide" ? "parentHide" : "";
                    if (triggerName.empty()) {
                        throw std::runtime_error("Storyboard trigger must be PointerDown, PointerUp, Toggled, Show, Hide, ParentShow or ParentHide");
                    }

                    output << "            " << variable << "->AddStoryboard({AnimationTrigger::"
                        << triggerName << ", {";
                    for (size_t index = 0; index < storyboard.children.size(); ++index) {
                        const Element& track = storyboard.children[index];
                        const auto attribute = [&track](const std::string& name) -> std::string {
                            const auto found = std::find_if(
                                track.attributes.begin(), track.attributes.end(),
                                [&name](const auto& value) { return value.first == name; });
                            return found == track.attributes.end() ? std::string{} : found->second;
                        };
                        if (!track.children.empty()) {
                            throw std::runtime_error("Animation tracks do not support child elements");
                        }
                        if (index != 0) {
                            output << ", ";
                        }
                        if (track.name == "ColorAnimation") {
                            this->EmitColorTrack(track, output);
                            continue;
                        }
                        if (track.name == "Animation") {
                            if (attribute("name").empty()) {
                                throw std::runtime_error("<Animation> requires name");
                            }
                            output << "[] { AnimationTrack track; track.name = \""
                                << this->EscapeCpp(attribute("name")) << "\";";
                            for (const auto& [key, value] : track.attributes) {
                                if (key != "name") {
                                    output << " track.settings.Set(\"" << this->EscapeCpp(key)
                                        << "\", \"" << this->EscapeCpp(value) << "\");";
                                }
                            }
                            output << " return track; }()";
                            continue;
                        }
                        const std::string property = track.name == "FloatAnimation" ? attribute("property") : "";
                        if (property != "opacity" && property != "renderOffsetX" && property != "renderOffsetY"
                            && property != "height"
                            && property != "toggleProgress" && property != "pressProgress") {
                            throw std::runtime_error("Unsupported animation track on <Storyboard>");
                        }
                        const std::string from = attribute("from");
                        const std::string to = attribute("to");
                        const std::string duration = attribute("duration");
                        const std::string easing = attribute("easing");
                        if (from.empty() || to.empty() || duration.empty()) {
                            throw std::runtime_error("Animation track requires from, to and duration");
                        }
                        const std::string easingName = easing.empty() || easing == "CubicOut" ? "cubicOut"
                            : easing == "Linear" ? "linear" : "";
                        if (easingName.empty()) {
                            throw std::runtime_error("Animation easing must be Linear or CubicOut");
                        }
                        const bool fromCurrent = from == "Current";
                        const bool toToggleState = to == "ToggleState";
                        output << "{AnimatedProperty::" << property << ", "
                            << (fromCurrent ? "0.0f" : this->FloatLiteral(from)) << ", "
                            << (toToggleState ? "0.0f" : this->FloatLiteral(to))
                            << ", " << (fromCurrent ? "true" : "false")
                            << ", " << (toToggleState ? "true" : "false")
                            << ", std::chrono::milliseconds(" << std::stoi(duration)
                            << "), Easing::" << easingName << "}";
                    }
                    output << "}});\n";
                }
            }
        }

        void EmitListViewItems(
            const Element& listView,
            const std::string& variable,
            std::ostringstream& output,
            std::map<std::string, size_t>& elementCounts,
            const std::string& bindingContext) {
            const auto source = std::find_if(
                listView.attributes.begin(),
                listView.attributes.end(),
                [](const auto& attribute) { return attribute.first == "itemsSource"; });
            if (source == listView.attributes.end()) {
                throw std::runtime_error("<ListView> requires itemsSource");
            }
            std::string sourceProperty;
            if (!this->TryGetBindingSource(source->second, sourceProperty)) {
                throw std::runtime_error("ListView itemsSource must use {Binding Property}");
            }
            const auto templateElement = std::find_if(
                listView.children.begin(),
                listView.children.end(),
                [](const Element& child) { return child.name == "ListView.ItemTemplate"; });
            if (templateElement == listView.children.end()
                || templateElement->children.size() != 1
                || templateElement->children.front().name != "DataTemplate"
                || templateElement->children.front().children.size() != 1) {
                throw std::runtime_error("<ListView.ItemTemplate> requires one <DataTemplate> with one root element");
            }
            const Element& templateRoot = templateElement->children.front().children.front();
            const std::string sourceExpression = sourceProperty == "ItemsSource"
                ? "itemsSource" : bindingContext + "." + sourceProperty + "()";
            output << "            " << variable << "->SetItemsSource(" << sourceExpression << ", [";
            if (sourceProperty == "ItemsSource") {
                output << "&viewModel, &itemsSource";
            } else if (bindingContext == "viewModel") {
                output << "&viewModel";
            } else {
                output << "&viewModel, &" << bindingContext;
            }
            output << "](const void* itemData, BindingScope& itemBindings) {\n";
            output << "            using Item = typename std::remove_reference_t<decltype(" << sourceExpression
                << ")>::value_type;\n";
            output << "            const auto& item = *static_cast<const Item*>(itemData);\n";
            output << "            BindingScope& bindings = itemBindings;\n";
            const std::string itemVariable = this->EmitElement(
                templateRoot,
                output,
                elementCounts,
                "item",
                "item");
            if (this->AttributeValue(templateRoot, "dataContext").empty()) {
                output << "            " << itemVariable << "->SetDataContext(static_cast<const void*>(&item));\n";
            }
            output << "            return " << itemVariable << ";\n";
            output << "            });\n";
        }

        void EmitGridDefinitions(
            const Element& grid,
            const std::string& variable,
            std::ostringstream& output) {
            const auto emitDefinitions = [this, &grid, &variable, &output](
                const std::string& collectionName,
                const std::string& definitionName,
                const std::string& valueName,
                const std::string& setterName) {
                for (const Element& collection : grid.children) {
                    if (collection.name != collectionName) {
                        continue;
                    }
                    std::ostringstream values;
                    for (size_t index = 0; index < collection.children.size(); ++index) {
                        const Element& definition = collection.children[index];
                        if (definition.name != definitionName) {
                            throw std::runtime_error("Only <" + definitionName + "> is allowed inside <"
                                + collectionName + ">");
                        }
                        const auto value = std::find_if(
                            definition.attributes.begin(), definition.attributes.end(),
                            [&valueName](const auto& attribute) { return attribute.first == valueName; });
                        if (value == definition.attributes.end()) {
                            throw std::runtime_error("<" + definitionName + "> requires " + valueName);
                        }
                        if (index != 0) {
                            values << ',';
                        }
                        values << value->second;
                    }
                    output << "            " << variable << "->Set" << setterName << "(\""
                        << this->EscapeCpp(values.str()) << "\");\n";
                    return;
                }
            };
            emitDefinitions("columnDefinitions", "columnDefinition", "width", "Columns");
            emitDefinitions("rowDefinitions", "rowDefinition", "height", "Rows");
        }

        std::string PropertyEnumName(const std::string& propertyName) {
            std::string result = propertyName;
            result.front() = static_cast<char>(result.front() - 'A' + 'a');
            return result;
        }

        void EmitBindingCall(
            const std::string& method,
            const std::vector<std::string>& arguments,
            std::ostringstream& output) {
            std::ostringstream singleLine;
            singleLine << "bindings." << method << "(";
            for (size_t index = 0; index < arguments.size(); ++index) {
                if (index != 0) {
                    singleLine << ", ";
                }
                singleLine << arguments[index];
            }
            singleLine << ");";
            if (12 + singleLine.str().size() <= 130) {
                output << "            " << singleLine.str() << "\n";
                return;
            }
            output << "            bindings." << method << "(\n";
            for (size_t index = 0; index < arguments.size(); ++index) {
                output << "                " << arguments[index];
                output << (index + 1 == arguments.size() ? "\n" : ",\n");
            }
            output << "            );\n";
        }

        void EmitBindings(const std::vector<Binding>& bindings, std::ostringstream& output) {
            for (const Binding& binding : bindings) {
                const std::string element = "*" + binding.elementVariable;
                const std::string source = binding.source;
                const std::string property = "std::remove_reference_t<decltype(" + source + ")>::Property::"
                    + this->PropertyEnumName(binding.sourceProperty);
                if (binding.property == "text") {
                    if (binding.mode == "twoWay") {
                        this->EmitBindingCall("AddTwoWay", {
                            element,
                            source,
                            "&TViewModel::" + binding.sourceProperty,
                            "&TViewModel::Set" + binding.sourceProperty,
                            "&Element::Text",
                            "&Element::SetText",
                            property,
                        }, output);
                    } else {
                        this->EmitBindingCall("AddOneWay", {
                            element,
                            source,
                            "&TViewModel::" + binding.sourceProperty,
                            "&Element::SetText",
                            property,
                        }, output);
                    }
                } else if (binding.property == "isOn") {
                    if (binding.mode == "twoWay") {
                        this->EmitBindingCall("AddTwoWay", {
                            element,
                            source,
                            "&TViewModel::" + binding.sourceProperty,
                            "&TViewModel::Set" + binding.sourceProperty,
                            "&Element::IsOn",
                            "&Element::SetIsOn",
                            property,
                        }, output);
                    } else {
                        this->EmitBindingCall("AddOneWay", {
                            element,
                            source,
                            "&TViewModel::" + binding.sourceProperty,
                            "&Element::SetIsOn",
                            property,
                        }, output);
                    }
                } else if (binding.property == "visibility") {
                    if (binding.mode == "twoWay") {
                        throw std::runtime_error("Visibility binding must be OneWay");
                    }
                    this->EmitBindingCall("AddOneWay", {
                        element,
                        source,
                        "&TViewModel::" + binding.sourceProperty,
                        "&Element::SetIsVisible",
                        property,
                    }, output);
                } else if (binding.property == "command") {
                    if (binding.mode == "twoWay") {
                        throw std::runtime_error("Command binding must be OneWay");
                    }
                    this->EmitBindingCall("AddCommand", {
                        element,
                        source,
                        "&TViewModel::" + binding.sourceProperty,
                    }, output);
                } else {
                    throw std::runtime_error("Unsupported binding target: " + binding.property);
                }
            }
        }

    };

    void XamlCompiler::Compile(
        const std::filesystem::path& input,
        const std::filesystem::path& outputPath,
        const std::vector<std::string>& ignoredDirectories,
        const std::vector<std::string>& ignoredFileSuffixes,
        std::string xamlNamespace,
        std::string controlXmlPrefix,
        std::string controlCppNamespace,
        std::string controlIncludePrefix) {
        this->xamlNamespace = std::move(xamlNamespace);
        this->controlXmlPrefix = std::move(controlXmlPrefix);
        this->controlCppNamespace = std::move(controlCppNamespace);
        if (this->IsIgnored(input, ignoredDirectories, ignoredFileSuffixes)) {
            std::cout << "XamlCompiler: skipping " << input.string() << '\n';
            return;
        }
        // Каждая XAML-страница получает собственный тип. Контроллеры работают
        // с MainPage::Create(), а не с неявной свободной функцией.
        const std::string source = this->ReadFile(input);
        this->xamlSource = &source;
        this->xamlSourcePath = std::filesystem::absolute(input).generic_string();
        const Element root = this->Parse(input, source);
        const auto namespaceAttribute = std::find_if(
            root.attributes.begin(),
            root.attributes.end(),
            [](const auto& attribute) { return attribute.first == "xmlns"; });
        if (namespaceAttribute == root.attributes.end()
            || namespaceAttribute->second != this->xamlNamespace) {
            throw std::runtime_error(
                "Root element must use xmlns=\"" + this->xamlNamespace + "\"");
        }
        const bool isPage = root.name == "Page";
        const bool isUserControl = root.name == "UserControl";
        if (!isPage && !isUserControl) {
            throw std::runtime_error("Root element must be <Page> or <UserControl>");
        }
        this->LoadResources(root);
        this->requiredControls.clear();
        const std::string typeName = input.stem().string();
        if (!std::regex_match(typeName, std::regex(R"([A-Za-z][A-Za-z0-9]*)"))) {
            throw std::runtime_error("XAML filename must be a valid C++ type name");
        }
        Element rootElement = root;
        if (isUserControl) {
            const std::string className = this->AttributeValue(root, "x:Class");
            if (this->controlCppNamespace.empty()) {
                throw std::runtime_error("UserControl requires --control-cpp-namespace");
            }
            if (className != this->controlCppNamespace + "::" + typeName) {
                throw std::runtime_error(
                    "<UserControl> requires x:Class=\"" + this->controlCppNamespace + "::" + typeName + "\"");
            }
            std::vector<Element> content;
            for (const Element& child : root.children) {
                if (child.name != "UserControl.Resources") {
                    content.push_back(child);
                }
            }
            if (content.size() != 1) {
                throw std::runtime_error("<UserControl> requires exactly one visual root element");
            }
            rootElement = std::move(content.front());
        }
        const std::filesystem::path headerPath = outputPath.parent_path()
            / (outputPath.stem().string() + ".h");

        std::ostringstream body;
        const std::string generatedTypeName = isUserControl ? typeName + "Xaml" : typeName;
        const std::string factoryMethod = isUserControl ? "BuildContent" : "Create";
        const bool usesItemsSource = isUserControl && this->UsesControlItemsSource(rootElement);
        body << "namespace xaml::generated {\n"
            << "    class " << generatedTypeName << " final {\n"
            << "    public:\n"
            << "        template <typename TViewModel" << (usesItemsSource ? ", typename TItemsSource" : "") << ">\n"
            << "        static std::unique_ptr<Element> " << factoryMethod
            << "(TViewModel& viewModel" << (usesItemsSource ? ", const TItemsSource& itemsSource" : "")
            << ", BindingScope& bindings) {\n";
        std::map<std::string, size_t> elementCounts;
        const std::string rootVariable = this->EmitElement(rootElement, body, elementCounts);
        if (this->AttributeValue(rootElement, "dataContext").empty()) {
            body << "            " << rootVariable << "->SetDataContext(static_cast<const void*>(&viewModel));\n";
        }
        body << "            return " << rootVariable << ";\n"
            << "        }\n"
            << "    };\n"
            << "}";

        std::ostringstream header;
        header << "// Сгенерировано XamlCompiler. Не редактировать вручную.\n"
            << "#pragma once\n"
            << "#include <UniversalDevKit/XamlRuntime/XamlLayout.h>\n"
            << "#include <UniversalDevKit/XamlRuntime/Binding.h>\n\n";
        std::vector<std::string> requiredControls(
            this->requiredControls.begin(),
            this->requiredControls.end());
        std::sort(
            requiredControls.begin(),
            requiredControls.end(),
            [](const std::string& left, const std::string& right) {
                return left.size() > right.size();
            });
        for (const std::string& control : requiredControls) {
            header << "#include \"" << controlIncludePrefix << "/" << control << ".h\"\n";
        }
        header << "\n#include <type_traits>\n\n" << body.str();

        std::ostringstream output;
        output << "// Сгенерировано XamlCompiler. Не редактировать вручную.\n"
            << "#include \"" << headerPath.filename().string() << "\"";
        std::filesystem::create_directories(outputPath.parent_path());
        std::ofstream headerFile(headerPath, std::ios::binary | std::ios::trunc);
        if (!headerFile) {
            throw std::runtime_error("Cannot write " + headerPath.string());
        }
        headerFile << header.str();
        std::ofstream file(outputPath, std::ios::binary | std::ios::trunc);
        if (!file) {
            throw std::runtime_error("Cannot write " + outputPath.string());
        }
        file << output.str();
    }
}

int main(int argc, char* argv[]) {
    if (argc < 3 || (argc - 3) % 2 != 0) {
        std::cerr << "Usage: XamlCompiler <input.xaml> <output.xaml.cpp> "
            "[--xaml-namespace <uri>] [--control-xml-prefix <prefix>] "
            "[--control-cpp-namespace <namespace>] [--control-include-prefix <path>] "
            "[--ignore-directory <name>] [--ignore-file-suffix <suffix>]\n";
        return 1;
    }
    try {
        std::vector<std::string> ignoredDirectories;
        std::vector<std::string> ignoredFileSuffixes;
        std::string xamlNamespace = "urn:xaml";
        std::string controlXmlPrefix;
        std::string controlCppNamespace;
        std::string controlIncludePrefix;
        for (int index = 3; index < argc; index += 2) {
            const std::string_view option = argv[index];
            const std::string value = argv[index + 1];
            if (option == "--ignore-directory") {
                if (!std::regex_match(value, std::regex(R"([A-Za-z][A-Za-z0-9_-]*)"))) {
                    throw std::runtime_error("Ignored directory name is invalid: " + value);
                }
                ignoredDirectories.push_back(value);
            } else if (option == "--ignore-file-suffix") {
                if (!std::regex_match(value, std::regex(R"([A-Za-z0-9_-]+)"))) {
                    throw std::runtime_error("Ignored file suffix is invalid: " + value);
                }
                ignoredFileSuffixes.push_back(value);
            } else if (option == "--xaml-namespace") {
                if (value.empty()) {
                    throw std::runtime_error("XAML namespace cannot be empty");
                }
                xamlNamespace = value;
            } else if (option == "--control-xml-prefix") {
                if (!std::regex_match(value, std::regex(R"([A-Za-z][A-Za-z0-9_.-]*)"))) {
                    throw std::runtime_error("Control XML prefix is invalid: " + value);
                }
                controlXmlPrefix = value;
            } else if (option == "--control-cpp-namespace") {
                if (!std::regex_match(value, std::regex(R"([A-Za-z][A-Za-z0-9_:]*)"))) {
                    throw std::runtime_error("Control C++ namespace is invalid: " + value);
                }
                controlCppNamespace = value;
            } else if (option == "--control-include-prefix") {
                if (!std::regex_match(value, std::regex(R"([A-Za-z][A-Za-z0-9_./-]*)"))) {
                    throw std::runtime_error("Control include prefix is invalid: " + value);
                }
                controlIncludePrefix = value;
            } else {
                throw std::runtime_error("Unknown argument: " + std::string(argv[index]));
            }
        }
        XamlCompiler compiler;
        compiler.Compile(
            argv[1],
            argv[2],
            ignoredDirectories,
            ignoredFileSuffixes,
            std::move(xamlNamespace),
            std::move(controlXmlPrefix),
            std::move(controlCppNamespace),
            std::move(controlIncludePrefix));
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "XamlCompiler: " << error.what() << '\n';
        return 1;
    }
}