#pragma once
#include "../Config.h"
#include "../Export.h"

#include "XamlAst.h"

#include <string_view>
#include <set>

namespace universaldevkit::xamlruntime::runtimemarkup {
    class UNIVERSALDEVKIT_XAMLRUNTIME_API XamlSchemaValidator final {
    public:
        void Validate(
            const XamlElementNode& root,
            std::string_view xamlNamespace,
            std::string_view controlXmlNamespace,
            const std::set<std::string>& controls = {});
    };
}