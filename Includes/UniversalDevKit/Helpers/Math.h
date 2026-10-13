#pragma once
#include "Export.h"

namespace universaldevkit::math {
    // Ноль не считается степенью двойки. Функция не изменяет общее состояние.
    UNIVERSALDEVKIT_HELPERS_API bool IsPowerOfTwo(unsigned int value) noexcept;

    // Возвращает результат умножения T; переполнение не проверяется.
    // Владение и исключения соответствуют копированию и operator* типа T.
    template<typename T>
    constexpr T Square(T value) {
        return value * value;
    }
}