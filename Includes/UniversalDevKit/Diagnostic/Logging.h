#pragma once
#include "Export.h"

#include <string_view>

namespace universaldevkit::diagnostic {
    UNIVERSALDEVKIT_DIAGNOSTIC_API void Log(std::string_view message);
}