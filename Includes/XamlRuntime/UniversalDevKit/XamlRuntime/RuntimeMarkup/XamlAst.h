#pragma once
#include "../Config.h"
#include "../Export.h"

#include <string>
#include <vector>

namespace universaldevkit::xamlruntime::runtimemarkup {
    struct XamlSourceLocation {
        std::string path;
        int line = 1;
        int column = 1;
    };

    struct XamlAttributeNode {
        std::string name;
        std::string value;
        XamlSourceLocation location;
        std::string nameSpace;
    };

    struct XamlElementNode {
        std::string name;
        std::string nameSpace;
        XamlSourceLocation location;
        std::vector<XamlAttributeNode> attributes;
        std::vector<XamlElementNode> children;
    };
}