#pragma once
#include <string_view>

#if defined(_WIN32) && defined(UNIVERSALDEVKIT_HELPERS_DYNAMIC)
#if defined(UNIVERSALDEVKIT_HELPERS_EXPORTS)
#define UNIVERSALDEVKIT_TEXT_API __declspec(dllexport)
#else
#define UNIVERSALDEVKIT_TEXT_API __declspec(dllimport)
#endif
#else
#define UNIVERSALDEVKIT_TEXT_API
#endif

namespace universaldevkit::text {
    UNIVERSALDEVKIT_TEXT_API bool EndsWithLineBreak(std::string_view text) noexcept;
}