#pragma once

#include <type_traits>
#include <utility>

namespace universaldevkit::meta {
    namespace detail {
        template<typename T, typename = void>
        struct is_dereferenceable : std::false_type {
        };

        template<typename T>
        struct is_dereferenceable<T, std::void_t<decltype(*std::declval<const T&>())>> : std::true_type {
        };

        template<typename T>
        inline constexpr bool is_dereferenceable_v = is_dereferenceable<T>::value;
    }

    class ValueExtractor {
    public:
        // Значение должно быть разыменовываемым до объекта; null не является допустимым входом.
        template<typename T>
        static decltype(auto) From(const T& value) {
            if constexpr (detail::is_dereferenceable_v<T>) {
                return From(*value);
            }
            else {
                return (value);
            }
        }
    };
}