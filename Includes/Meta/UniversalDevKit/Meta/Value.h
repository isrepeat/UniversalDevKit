#pragma once
#include <UniversalDevKit/Meta/Concepts.h>

namespace universaldevkit::meta {
    class ValueExtractor {
    public:
        // Значение должно быть разыменовываемым до объекта; null не является допустимым входом.
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