#pragma once
#include "XamlAst.h"

#include <stdexcept>

namespace xaml::runtime {
    class RuntimeDiagnostic final : public std::runtime_error {
    public:
        RuntimeDiagnostic(const XamlSourceLocation& location, const std::string& message);
    };
}