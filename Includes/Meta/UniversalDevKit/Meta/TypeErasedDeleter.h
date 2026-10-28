#pragma once

namespace universaldevkit::meta {
    struct TypeErasedDeleter {
        using Function = void(*)(void*);

        constexpr TypeErasedDeleter() noexcept = default;

        explicit constexpr TypeErasedDeleter(Function function) noexcept
            : function(function) {
        }

        void operator()(void* value) const {
            if (function != nullptr) {
                function(value);
            }
        }

        template<typename T>
        static constexpr TypeErasedDeleter Make() noexcept {
            return TypeErasedDeleter{
                [](void* value) {
                    delete static_cast<T*>(value);
                }
            };
        }

    private:
        Function function{ nullptr };
    };
}