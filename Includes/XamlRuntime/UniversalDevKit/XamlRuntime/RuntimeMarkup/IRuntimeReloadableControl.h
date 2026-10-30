#pragma once
#include "RuntimeBindingContext.h"

namespace xaml::runtime {
    class IRuntimeReloadableControl {
    public:
        virtual ~IRuntimeReloadableControl() = default;
        virtual std::string_view RuntimeClassName() const = 0;
        virtual bool ReplaceTemplate(const XamlElementNode& templateNode,
            const RuntimeBindingContext& context, std::string& diagnostics) = 0;
    };
}