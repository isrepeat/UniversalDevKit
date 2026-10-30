#include "../../../Includes/XamlRuntime/UniversalDevKit/XamlRuntime/RuntimeMarkup/XamlParser.h"

#include "../../../Includes/XamlRuntime/UniversalDevKit/XamlRuntime/RuntimeMarkup/RuntimeDiagnostics.h"

#include <cctype>
#include <set>

namespace universaldevkit::xamlruntime::runtimemarkup::details {
    std::string Resolve(std::string& name, const std::map<std::string, std::string>& namespaces,
        const XamlSourceLocation& location, bool attribute) {
        const auto colon = name.find(':');
        const std::string prefix = colon == std::string::npos ? "" : name.substr(0, colon);
        if (colon == std::string::npos && attribute) {
            return {};
        }
        const auto found = namespaces.find(prefix);
        if (found == namespaces.end()) {
            throw RuntimeDiagnostic(location, "Undeclared XML namespace '" + prefix + "'");
        }
        if (colon != std::string::npos) {
            name.erase(0, colon + 1);
        }
        return found->second;
    }
}

namespace universaldevkit::xamlruntime::runtimemarkup {
    RuntimeDiagnostic::RuntimeDiagnostic(const XamlSourceLocation& location, const std::string& message)
        : std::runtime_error(location.path + ":" + std::to_string(location.line) + ":"
            + std::to_string(location.column) + ": " + message) {
    }

    //
    // API
    //
    XamlElementNode XamlParser::Parse(std::string_view markup, std::string_view sourcePath) {
        this->markup = markup;
        this->path = sourcePath;
        this->offset = 0;
        this->line = 1;
        this->column = 1;
        if (this->Starts("\xEF\xBB\xBF")) {
            this->offset = 3;
        }
        this->SkipMisc();
        auto root = this->ReadElement({{"xml", "http://www.w3.org/XML/1998/namespace"}}, 0);
        this->SkipMisc();
        if (this->offset != this->markup.size()) {
            throw RuntimeDiagnostic(this->Location(), "Unexpected content after root element");
        }
        return root;
    }

    //
    // Internal
    //
    XamlSourceLocation XamlParser::Location() const {
        return {this->path, this->line, this->column};
    }

    bool XamlParser::Starts(std::string_view value) const {
        return this->markup.substr(this->offset, value.size()) == value;
    }

    void XamlParser::Advance() {
        if (this->offset >= this->markup.size()) {
            throw RuntimeDiagnostic(this->Location(), "Unexpected end of XML");
        }
        const unsigned char value = this->markup[this->offset++];
        if (value == '\n') {
            ++this->line;
            this->column = 1;
        } else if ((value & 0xC0) != 0x80) {
            ++this->column;
        }
    }

    void XamlParser::Expect(std::string_view value) {
        if (!this->Starts(value)) {
            throw RuntimeDiagnostic(this->Location(), "Expected '" + std::string(value) + "'");
        }
        for (size_t index = 0; index < value.size(); ++index) {
            this->Advance();
        }
    }

    void XamlParser::SkipSpace() {
        while (this->offset < this->markup.size() && std::isspace(static_cast<unsigned char>(this->markup[this->offset]))) {
            this->Advance();
        }
    }

    void XamlParser::SkipMisc() {
        while (true) {
            this->SkipSpace();
            const std::string end = this->Starts("<!--") ? "-->" : this->Starts("<?") ? "?>" : "";
            if (end.empty()) {
                return;
            }
            this->Expect(end == "-->" ? "<!--" : "<?");
            while (!this->Starts(end)) {
                this->Advance();
            }
            this->Expect(end);
        }
    }

    std::string XamlParser::Name() {
        const auto start = this->offset;
        while (this->offset < this->markup.size()) {
            const unsigned char value = this->markup[this->offset];
            if (!(std::isalnum(value) || value == '_' || value == ':' || value == '.' || value == '-')) {
                break;
            }
            this->Advance();
        }
        if (start == this->offset || std::isdigit(static_cast<unsigned char>(this->markup[start]))) {
            throw RuntimeDiagnostic(this->Location(), "Expected XML name");
        }
        return std::string(this->markup.substr(start, this->offset - start));
    }

    std::string XamlParser::Value() {
        if (!this->Starts("\"") && !this->Starts("'")) {
            throw RuntimeDiagnostic(this->Location(), "Expected quoted attribute value");
        }
        const char quote = this->markup[this->offset];
        this->Advance();
        std::string result;
        while (!this->Starts(std::string(1, quote))) {
            if (this->Starts("<")) {
                throw RuntimeDiagnostic(this->Location(), "Unescaped '<' in attribute");
            }
            if (this->Starts("&")) {
                this->Advance();
                const auto start = this->offset;
                while (!this->Starts(";")) {
                    this->Advance();
                }
                const std::string entity(this->markup.substr(start, this->offset - start));
                this->Advance();
                const std::map<std::string, std::string> entities{{"amp", "&"}, {"lt", "<"}, {"gt", ">"}, {"quot", "\""}, {"apos", "'"}};
                const auto found = entities.find(entity);
                if (found != entities.end()) {
                    result += found->second;
                } else if (!entity.empty() && entity[0] == '#') {
                    try {
                        size_t consumed = 0;
                        const bool hex = entity.size() > 1 && entity[1] == 'x';
                        const auto digits = entity.substr(hex ? 2 : 1);
                        const auto code = std::stoul(digits, &consumed, hex ? 16 : 10);
                        if (consumed != digits.size() || code == 0 || code > 0x10FFFF || (code >= 0xD800 && code <= 0xDFFF)) {
                            throw std::invalid_argument("character");
                        }
                        if (code < 0x80) {
                            result += static_cast<char>(code);
                        } else {
                            if (code >= 0x10000) {
                                result += static_cast<char>(0xF0 | (code >> 18));
                                result += static_cast<char>(0x80 | ((code >> 12) & 63));
                            } else if (code >= 0x800) {
                                result += static_cast<char>(0xE0 | (code >> 12));
                            } else {
                                result += static_cast<char>(0xC0 | (code >> 6));
                            }
                            if (code >= 0x800) {
                                result += static_cast<char>(0x80 | ((code >> 6) & 63));
                            }
                            result += static_cast<char>(0x80 | (code & 63));
                        }
                    } catch (const std::exception&) {
                        throw RuntimeDiagnostic(this->Location(), "Invalid XML character reference");
                    }
                } else {
                    throw RuntimeDiagnostic(this->Location(), "Unknown XML entity '" + entity + "'");
                }
            } else {
                if (this->offset >= this->markup.size()) {
                    throw RuntimeDiagnostic(this->Location(), "Unterminated attribute");
                }
                result += this->markup[this->offset];
                this->Advance();
            }
        }
        this->Advance();
        return result;
    }

    XamlElementNode XamlParser::ReadElement(std::map<std::string, std::string> namespaces, size_t depth) {
        if (depth > 256) {
            throw RuntimeDiagnostic(this->Location(), "XML nesting exceeds 256 levels");
        }
        XamlElementNode node;
        node.location = this->Location();
        this->Expect("<");
        const std::string qualified = this->Name();
        node.name = qualified;
        std::set<std::string> names;
        while (true) {
            const auto beforeSpace = this->offset;
            this->SkipSpace();
            if (this->Starts(">") || this->Starts("/>")) {
                break;
            }
            if (this->offset == beforeSpace) {
                throw RuntimeDiagnostic(this->Location(), "Expected whitespace before attribute");
            }
            XamlAttributeNode attribute;
            attribute.location = this->Location();
            attribute.name = this->Name();
            if (!names.insert(attribute.name).second) {
                throw RuntimeDiagnostic(attribute.location, "Duplicate attribute '" + attribute.name + "'");
            }
            this->SkipSpace();
            this->Expect("=");
            this->SkipSpace();
            attribute.value = this->Value();
            if (attribute.name == "xmlns") {
                namespaces[""] = attribute.value;
            } else if (attribute.name.rfind("xmlns:", 0) == 0) {
                namespaces[attribute.name.substr(6)] = attribute.value;
            } else {
                node.attributes.push_back(std::move(attribute));
            }
        }
        node.nameSpace = details::Resolve(node.name, namespaces, node.location, false);
        names.clear();
        for (auto& attribute : node.attributes) {
            attribute.nameSpace = details::Resolve(attribute.name, namespaces, attribute.location, true);
            if (!names.insert(attribute.nameSpace + "|" + attribute.name).second) {
                throw RuntimeDiagnostic(attribute.location, "Duplicate expanded attribute name");
            }
        }
        if (this->Starts("/>")) {
            this->Expect("/>");
            return node;
        }
        this->Expect(">");
        while (true) {
            this->SkipMisc();
            if (this->Starts("</")) {
                this->Expect("</");
                if (this->Name() != qualified) {
                    throw RuntimeDiagnostic(this->Location(), "Mismatched closing tag for " + qualified);
                }
                this->SkipSpace();
                this->Expect(">");
                return node;
            }
            node.children.push_back(this->ReadElement(namespaces, depth + 1));
        }
    }
}