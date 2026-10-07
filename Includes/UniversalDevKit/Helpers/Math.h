#pragma once

#if defined(_WIN32) && defined(UNIVERSALDEVKIT_HELPERS_DYNAMIC)
#if defined(UNIVERSALDEVKIT_HELPERS_EXPORTS)
#define UNIVERSALDEVKIT_HELPERS_API __declspec(dllexport)
#else
#define UNIVERSALDEVKIT_HELPERS_API __declspec(dllimport)
#endif
#else
#define UNIVERSALDEVKIT_HELPERS_API
#endif

namespace universaldevkit::math {
    UNIVERSALDEVKIT_HELPERS_API bool IsPowerOfTwo(unsigned int value) noexcept;

    template<typename T>
    constexpr T Square(T value) {
        return value * value;
    }
}