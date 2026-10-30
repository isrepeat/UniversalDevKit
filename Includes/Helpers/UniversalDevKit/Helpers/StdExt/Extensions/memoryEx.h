#pragma once
#include "../Config.h"

#include <type_traits>
#include <concepts>
#include <typeinfo>
#include <utility>
#include <memory>

namespace universaldevkit::helpers::stdext::extensions {
    namespace concepts {
        template <typename T, typename U>
        concept dynamic_castable = !std::is_array_v<T> && !std::is_array_v<U> &&
            requires(T* pointer) { dynamic_cast<U*>(pointer); };

        template <typename T, typename U, typename TDeleter>
        concept safe_unique_cast = !std::is_array_v<T> && !std::is_array_v<U> &&
            std::same_as<TDeleter, std::default_delete<T>> &&
            (std::same_as<T, U> || std::has_virtual_destructor_v<U> || std::is_final_v<U>) &&
            dynamic_castable<T, U>;
    } // namespace concepts

    //
    // unique_ptr
    //
    template <typename T, typename TDeleter = std::default_delete<T>>
    struct unique_ptr : public std::unique_ptr<T, TDeleter> {
        using Base_t = std::unique_ptr<T, TDeleter>;
        using Base_t::unique_ptr; // Special member constructors are not inherited; provide bridges below.

        //PP_FORWARD_CTOR(unique_ptr, std::unique_ptr<T>);
        unique_ptr(Base_t&& other) noexcept
            : Base_t{std::move(other)} {
        }

        // Check the type without changing ownership.
        template <typename U>
        __requires_expr(concepts::dynamic_castable<T, U> && requires(typename Base_t::pointer pointer) { dynamic_cast<U*>(pointer); })
        bool Is() const {
            return dynamic_cast<U*>(this->get()) != nullptr;
        }

        // Return an observing view without changing ownership.
        template <typename U>
        __requires_expr(concepts::dynamic_castable<T, U> && requires(typename Base_t::pointer pointer) { dynamic_cast<U*>(pointer); })
        U* AsView() const {
            return dynamic_cast<U*>(this->get());
        }

        // Transfer default-deleter ownership only when deletion through U is safe.
        // Require an rvalue to make the ownership transfer explicit.
        template <typename U>
        __requires_expr(concepts::safe_unique_cast<T, U, TDeleter>)
        unique_ptr<U> As() && {
            T* const rawPtr = this->get();
            if (U* const casted = dynamic_cast<U*>(rawPtr)) {
                (void)this->release(); // Release ownership only after a successful cast.
                return unique_ptr<U>{casted};
            }
            return {};
        }

        // Throw std::bad_cast if the cast fails.
        template <typename U>
        __requires_expr(concepts::safe_unique_cast<T, U, TDeleter>)
        unique_ptr<U> Cast() && {
            T* const rawPtr = this->get();
            if (U* const casted = dynamic_cast<U*>(rawPtr)) {
                (void)this->release();
                return unique_ptr<U>{casted};
            }
            throw std::bad_cast{};
        }
    };

    // Wrap std::make_unique and return stdEx::unique_ptr<T>.
    template <typename T, typename... Args>
    unique_ptr<T> make_unique_ex(Args&&... args) {
        return unique_ptr<T>(std::make_unique<T>(std::forward<Args>(args)...));
    }

    //
    // shared_ptr
    //
    template <typename T>
    struct shared_ptr : public std::shared_ptr<T> {
        using Base_t = std::shared_ptr<T>;
        using Base_t::shared_ptr;

        //PP_FORWARD_CTOR(shared_ptr, std::shared_ptr<T>);
        shared_ptr(const Base_t& other)
            : Base_t{other} {
        }

        shared_ptr(Base_t&& other) noexcept
            : Base_t{std::move(other)} {
        }

        template <typename U>
        __requires_expr(concepts::dynamic_castable<T, U>)
        bool Is() const {
            return std::dynamic_pointer_cast<U>(*this) != nullptr;
        }

        template <typename U>
        __requires_expr(concepts::dynamic_castable<T, U>)
        shared_ptr<U> As() const {
            auto casted = std::dynamic_pointer_cast<U>(*this);
            return casted;
        }

        template <typename U>
        __requires_expr(concepts::dynamic_castable<T, U>)
        shared_ptr<U> Cast() const {
            auto casted = std::dynamic_pointer_cast<U>(*this);
            if (casted == nullptr) {
                throw std::bad_cast{};
            }
            return casted;
        }
    };

    // Wrap std::make_shared and return stdEx::shared_ptr<T>.
    template <typename T, typename... Args>
    shared_ptr<T> make_shared_ex(Args&&... args) {
        return shared_ptr<T>(std::make_shared<T>(std::forward<Args>(args)...));
    }

    //
    // weak_ptr
    //
    template <typename T>
    struct weak_ptr : public std::weak_ptr<T> {
        using Base_t = std::weak_ptr<T>;
        using Base_t::weak_ptr;

        //PP_FORWARD_CTOR(weak_ptr, std::weak_ptr<T>);
        weak_ptr(const Base_t& other)
            : Base_t{other} {
        }

        weak_ptr(Base_t&& other) noexcept
            : Base_t{std::move(other)} {
        }

        // override to retrun extensible struct
        shared_ptr<T> lock() const {
            return std::weak_ptr<T>::lock();
        }

    };
}