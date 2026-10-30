#pragma once
#include "../Config.h"
#include "../Export.h"

#include "RuntimeBindingRegistry.h"
#include "XamlAst.h"

#include <functional>
#include <memory>
#include <string>
#include <map>

namespace universaldevkit::xamlruntime::runtimemarkup {
    struct RuntimeBindingContext {
        std::shared_ptr<RuntimeBindingRegistry> bindings;
        std::string owner;
        std::map<std::string, std::function<std::unique_ptr<Element>(BindingScope&)>> controls;
        std::function<void(Element&)> prepareTree;
        std::function<void()> beforeCommit;
        std::string xamlNamespace = "urn:xaml";
        std::string controlXmlNamespace;
    };
}