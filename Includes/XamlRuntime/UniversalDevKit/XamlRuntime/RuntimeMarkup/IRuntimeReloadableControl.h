#pragma once
#include "../Config.h"
#include "../Export.h"

#include "RuntimeBindingContext.h"

namespace universaldevkit::xamlruntime::runtimemarkup {
    class IRuntimeReloadableControl {
    public:
        virtual ~IRuntimeReloadableControl() = default;
        virtual std::string_view RuntimeClassName() const = 0;
        virtual bool ReplaceTemplate(const XamlElementNode& templateNode,
            const RuntimeBindingContext& context, std::string& diagnostics) = 0;
    };
}