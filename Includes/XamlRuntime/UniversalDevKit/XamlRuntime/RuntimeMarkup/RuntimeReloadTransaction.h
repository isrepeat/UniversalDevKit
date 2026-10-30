#pragma once
#include "RuntimeTreeBuilder.h"

namespace xaml::runtime {
    class RuntimeReloadTransaction final {
    public:
        RuntimeBuildResult Prepare(std::string_view markup, std::string_view sourcePath,
            const RuntimeBindingContext& context, const Element& previous, Size availableSize);
    };
}