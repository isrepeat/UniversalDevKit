#pragma once
#include "XamlAst.h"

#include <set>
#include <string_view>

namespace xaml::runtime {
    class XamlSchemaValidator final {
    public:
        void Validate(
            const XamlElementNode& root,
            std::string_view xamlNamespace,
            std::string_view controlXmlNamespace,
            const std::set<std::string>& controls = {});
    };
}