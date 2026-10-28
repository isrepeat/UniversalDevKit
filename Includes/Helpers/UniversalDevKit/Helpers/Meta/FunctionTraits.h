#pragma once
#include <UniversalDevKit/Helpers/Meta/Concepts.h>

#include <type_traits>
#include <concepts>
#include <cstddef>
#include <tuple>

namespace universaldevkit::helpers::meta {
    //
    // ░ API: function categories and qualifiers
    // ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
    //
    enum class FuncKind {
        Functor,
        CstyleFunc,
        ClassMember
    };

    enum class RefQual {
        None,
        LValue,
        RValue
    };

    template<typename TFunction>
    struct FunctionTraits;

    namespace detail {
        // Form the member pointer type used to select a specific operator().
        template<typename TClass, typename TSignature>
        __requires_expr(
            (std::is_class_v<TClass> || std::is_union_v<TClass>) &&
            std::is_function_v<TSignature>
        )
        struct CallOperatorPointer {
            using type = TSignature TClass::*;
        };
    }

    namespace concepts {
        //
        // ░ API: concepts for function and member function checks
        // ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
        //
        template<typename TFunction>
        concept has_non_overloaded_call_op = requires { &std::remove_cvref_t<TFunction>::operator(); };

        template<typename TFunction, typename TSignature>
        concept has_call_op_with_signature = requires {
            static_cast<typename detail::CallOperatorPointer<std::remove_cvref_t<TFunction>, TSignature>::type>(
                &std::remove_cvref_t<TFunction>::operator());
        };

        // Dependent members are checked when the complete FunctionTraits is instantiated.
        template<typename TFunction>
        concept has_method = requires { FunctionTraits<TFunction>::Kind; } &&
            FunctionTraits<TFunction>::Kind == FuncKind::ClassMember;

        template<typename TFunction, typename TSignature>
        concept has_method_with_signature = has_method<TFunction> &&
            std::same_as<typename FunctionTraits<TFunction>::Signature, TSignature>;

        template<typename TFunction>
        concept has_static_function = requires { FunctionTraits<TFunction>::Kind; } &&
            FunctionTraits<TFunction>::Kind == FuncKind::CstyleFunc;

        template<typename TFunction, typename TSignature>
        concept has_static_function_with_signature = has_static_function<TFunction> &&
            std::same_as<typename FunctionTraits<TFunction>::Signature, TSignature>;
    }

    namespace detail {
        //
        // ░ Implementation: return type and function arguments
        // ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
        //
        template<typename TResult, typename... TArguments>
        struct FunctionArguments {
            static constexpr std::size_t ArgumentCount = sizeof...(TArguments);
            using Ret = TResult;
            using Arguments = std::tuple<TArguments...>;

            template<std::size_t Index>
            struct arg {
                using type = std::tuple_element_t<Index, Arguments>;
            };

            template<std::size_t Index>
            struct arg_val {
                using type = std::remove_pointer_t<std::remove_reference_t<typename arg<Index>::type>>;
            };
        };

        //
        // ░ Implementation: free functions and function pointers
        // ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
        //
        // The empty primary template lets requires expressions detect unsupported types.
        template<typename T>
        struct FunctionDescription {
        };

        template<typename TResult, typename... TArguments, bool Noexcept>
        struct FunctionDescription<TResult(*)(TArguments...) noexcept(Noexcept)> : FunctionArguments<TResult, TArguments...> {
            using Class = void;
            using Signature = TResult(*)(TArguments...) noexcept(Noexcept);
            static constexpr FuncKind Kind = FuncKind::CstyleFunc;
            static constexpr bool IsConst = false;
            static constexpr bool IsVolatile = false;
            static constexpr bool IsNoexcept = Noexcept;
            static constexpr RefQual Ref = RefQual::None;
        };

        template<typename TResult, typename... TArguments, bool Noexcept>
        struct FunctionDescription<TResult(TArguments...) noexcept(Noexcept)> : FunctionDescription<TResult(*)(TArguments...) noexcept(Noexcept)> {
        };

        //
        // ░ Implementation: member function pointers, cv/ref/noexcept
        // ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
        //
        // The cv/ref qualifier matrix covers both ordinary and noexcept member functions.
#define UNIVERSALDEVKIT_META_MEMBER_TRAITS(Cv, Reference, ConstValue, VolatileValue, RefValue) \
        template<typename TResult, typename TClass, typename... TArguments, bool Noexcept> \
        struct FunctionDescription<TResult(TClass::*)(TArguments...) Cv Reference noexcept(Noexcept)> \
            : FunctionArguments<TResult, TArguments...> { \
            using Class = TClass; \
            using Signature = TResult(TClass::*)(TArguments...) Cv Reference noexcept(Noexcept); \
            static constexpr FuncKind Kind = FuncKind::ClassMember; \
            static constexpr bool IsConst = ConstValue; \
            static constexpr bool IsVolatile = VolatileValue; \
            static constexpr bool IsNoexcept = Noexcept; \
            static constexpr RefQual Ref = RefValue; \
        };

        UNIVERSALDEVKIT_META_MEMBER_TRAITS(, , false, false, RefQual::None)
        UNIVERSALDEVKIT_META_MEMBER_TRAITS(const, , true, false, RefQual::None)
        UNIVERSALDEVKIT_META_MEMBER_TRAITS(volatile, , false, true, RefQual::None)
        UNIVERSALDEVKIT_META_MEMBER_TRAITS(const volatile, , true, true, RefQual::None)
        UNIVERSALDEVKIT_META_MEMBER_TRAITS(, &, false, false, RefQual::LValue)
        UNIVERSALDEVKIT_META_MEMBER_TRAITS(const, &, true, false, RefQual::LValue)
        UNIVERSALDEVKIT_META_MEMBER_TRAITS(volatile, &, false, true, RefQual::LValue)
        UNIVERSALDEVKIT_META_MEMBER_TRAITS(const volatile, &, true, true, RefQual::LValue)
        UNIVERSALDEVKIT_META_MEMBER_TRAITS(, &&, false, false, RefQual::RValue)
        UNIVERSALDEVKIT_META_MEMBER_TRAITS(const, &&, true, false, RefQual::RValue)
        UNIVERSALDEVKIT_META_MEMBER_TRAITS(volatile, &&, false, true, RefQual::RValue)
        UNIVERSALDEVKIT_META_MEMBER_TRAITS(const volatile, &&, true, true, RefQual::RValue)

#undef UNIVERSALDEVKIT_META_MEMBER_TRAITS

        //
        // ░ Implementation: functors and operator() selection
        // ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
        //
        template<typename T>
        __requires_expr(
            concepts::has_non_overloaded_call_op<T>
        )
        struct FunctionDescription<T> : FunctionDescription<decltype(&T::operator())> {
            static constexpr FuncKind Kind = FuncKind::Functor;
        };

    }

    //
    // ░ API: FunctionTraits and explicit call signatures
    // ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
    //
    // An overloaded or templated operator() requires an explicit signature.
    template<typename TFunction>
    struct FunctionTraits : detail::FunctionDescription<std::remove_cvref_t<TFunction>> {
    };

    template<typename TFunction, typename TSignature>
    __requires_expr(
        concepts::has_call_op_with_signature<TFunction, TSignature>
    )
    struct FunctionTraitsWithSignature : FunctionTraits<typename detail::CallOperatorPointer<std::remove_cvref_t<TFunction>, TSignature>::type> {
        static constexpr FuncKind Kind = FuncKind::Functor;
    };
}