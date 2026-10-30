#pragma once
#include "../Concepts.h"

namespace universaldevkit::helpers::meta::utilities {
    class ValueExtractor {
    public:
        // Dereferencing must eventually reach an object; null pointers are not valid input.
        template<typename T>
        static decltype(auto) From(const T& value) {
            if constexpr (concepts::Dereferenceable<T>) {
                return From(*value);
            }
            else {
                return (value);
            }
        }
    };
}