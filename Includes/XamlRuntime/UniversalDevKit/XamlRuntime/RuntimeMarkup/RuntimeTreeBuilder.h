#pragma once
#include "../Config.h"
#include "../Export.h"

#include "RuntimeBindingContext.h"

namespace universaldevkit::xamlruntime::runtimemarkup {
    struct RuntimeBuildResult {
        std::unique_ptr<Element> root;
        std::unique_ptr<BindingScope> bindings;
    };

    class UNIVERSALDEVKIT_XAMLRUNTIME_API RuntimeTreeBuilder final {
    public:
        RuntimeBuildResult BuildPage(const XamlElementNode& root, const RuntimeBindingContext& context, Size availableSize);
        std::unique_ptr<Element> BuildElement(const XamlElementNode& node, const RuntimeBindingContext& context, BindingScope& bindings);
    };
}