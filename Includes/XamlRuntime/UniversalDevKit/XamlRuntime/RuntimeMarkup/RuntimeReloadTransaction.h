#pragma once
#include "../Config.h"
#include "../Export.h"

#include "RuntimeTreeBuilder.h"

namespace universaldevkit::xamlruntime::runtimemarkup {
    class UNIVERSALDEVKIT_XAMLRUNTIME_API RuntimeReloadTransaction final {
    public:
        RuntimeBuildResult Prepare(std::string_view markup, std::string_view sourcePath,
            const RuntimeBindingContext& context, const Element& previous, Size availableSize);
    };
}