#pragma once

namespace universaldevkit::helpers::meta {
    // Always false, but dependent on the template arguments.
    template<typename...>
    inline constexpr bool dependent_false_v = false;
}