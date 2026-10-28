#pragma once
#include <type_traits>

namespace universaldevkit::meta {
    //
    // ░ Conditional compile-time value selection
    // ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
    //
    // Select the value and its type without requiring a common type for both branches.
    template<bool Condition, auto TrueValue, auto FalseValue>
    struct IF_value_c : std::integral_constant<decltype(TrueValue), TrueValue> {
    };

    template<auto TrueValue, auto FalseValue>
    struct IF_value_c<false, TrueValue, FalseValue> : std::integral_constant<decltype(FalseValue), FalseValue> {
    };
}