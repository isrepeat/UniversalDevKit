#pragma once
#include "../Config.h"
#include <UniversalDevKit/XamlRuntime/Export.g.h>

#include "XamlAst.h"

#include <stdexcept>

namespace universaldevkit::xamlruntime::runtimemarkup {
    class UNIVERSALDEVKIT_XAMLRUNTIME_API RuntimeDiagnostic final : public std::runtime_error {
    public:
        RuntimeDiagnostic(const XamlSourceLocation& location, const std::string& message);
    };
}