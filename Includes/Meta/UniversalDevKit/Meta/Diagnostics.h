#pragma once

#include <type_traits>

namespace universaldevkit::meta {
    // Значение всегда ложно, но зависит от параметров шаблона.
    template<typename...>
    inline constexpr bool dependent_false_v = false;
}