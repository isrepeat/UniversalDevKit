#pragma once
#include <memory>

namespace universaldevkit::helpers::meta::utilities {
    class PointerGetter {
    public:
        template<typename T>
        static constexpr T* Get(T* value) noexcept {
            return value;
        }

        template<typename T>
        static constexpr const T* Get(const T* value) noexcept {
            return value;
        }

        template<typename T>
        static constexpr T* Get(T& value) noexcept {
            return std::addressof(value);
        }

        template<typename T>
        static constexpr const T* Get(const T& value) noexcept {
            return std::addressof(value);
        }

        template<typename T>
        static T* Get(std::unique_ptr<T>& value) noexcept {
            return value.get();
        }

        template<typename T>
        static const T* Get(const std::unique_ptr<T>& value) noexcept {
            return value.get();
        }

        template<typename T>
        static T* Get(std::shared_ptr<T>& value) noexcept {
            return value.get();
        }

        template<typename T>
        static const T* Get(const std::shared_ptr<T>& value) noexcept {
            return value.get();
        }
    };
}