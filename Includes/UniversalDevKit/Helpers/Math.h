#pragma once
#include "Export.h"

namespace universaldevkit::math {
    UNIVERSALDEVKIT_HELPERS_API bool IsPowerOfTwo(unsigned int value) noexcept;

    template<typename T>
    constexpr T Square(T value) {
        return value * value;
    }
}