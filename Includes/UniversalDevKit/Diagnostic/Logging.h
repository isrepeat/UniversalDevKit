#pragma once

#include <string_view>

#if defined(_WIN32) && defined(UNIVERSALDEVKIT_DIAGNOSTIC_DYNAMIC)
#if defined(UNIVERSALDEVKIT_DIAGNOSTIC_EXPORTS)
#define UNIVERSALDEVKIT_DIAGNOSTIC_API __declspec(dllexport)
#else
#define UNIVERSALDEVKIT_DIAGNOSTIC_API __declspec(dllimport)
#endif
#else
#define UNIVERSALDEVKIT_DIAGNOSTIC_API
#endif

namespace universaldevkit::diagnostic {
    UNIVERSALDEVKIT_DIAGNOSTIC_API void Log(std::string_view message);
}