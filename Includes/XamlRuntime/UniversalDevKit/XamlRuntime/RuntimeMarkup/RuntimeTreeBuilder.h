#pragma once
#include "RuntimeBindingContext.h"

namespace xaml::runtime {
    struct RuntimeBuildResult {
        std::unique_ptr<Element> root;
        std::unique_ptr<BindingScope> bindings;
    };

    class RuntimeTreeBuilder final {
    public:
        RuntimeBuildResult BuildPage(const XamlElementNode& root, const RuntimeBindingContext& context, Size availableSize);
        std::unique_ptr<Element> BuildElement(const XamlElementNode& node, const RuntimeBindingContext& context, BindingScope& bindings);
    };
}