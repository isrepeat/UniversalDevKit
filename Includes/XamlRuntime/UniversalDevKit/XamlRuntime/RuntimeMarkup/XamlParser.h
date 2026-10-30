#pragma once
#include "XamlAst.h"

#include <string_view>
#include <map>

namespace xaml::runtime {
    class XamlParser final {
    public:
        XamlElementNode Parse(std::string_view markup, std::string_view sourcePath);

    private:
        XamlSourceLocation Location() const;
        bool Starts(std::string_view value) const;
        void Advance();
        void Expect(std::string_view value);
        void SkipSpace();
        void SkipMisc();
        std::string Name();
        std::string Value();
        XamlElementNode ReadElement(std::map<std::string, std::string> namespaces, size_t depth);

    private:
        std::string_view markup;
        std::string path;
        size_t offset = 0;
        int line = 1;
        int column = 1;
    };
}