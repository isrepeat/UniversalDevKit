#include <UniversalDevKit/Meta/FunctionTraits.h>
#include <UniversalDevKit/Meta/Concepts.h>
#include <UniversalDevKit/Meta/Logic.h>

#include <type_traits>
#include <vector>
#include <array>

namespace meta = universaldevkit::meta;

namespace {
    int FreeFunction(int value) noexcept { return value + 1; }

    struct Callable {
        int operator()(int value) const & noexcept { return value + 2; }
    };

    struct Overloaded {
        int operator()(int value) const noexcept { return value + 3; }
        double operator()(double value) const { return value; }
    };

    struct Members {
        int Plain(const int*, double&);
        int Const() const;
        int Volatile() volatile;
        int ConstVolatile() const volatile;
        int LValue() &;
        int ConstLValue() const &;
        int VolatileLValue() volatile &;
        int ConstVolatileLValue() const volatile &;
        int RValue() &&;
        int ConstRValue() const &&;
        int VolatileRValue() volatile &&;
        int ConstVolatileRValue() const volatile &&;
    };

    // Проверяем cv/ref-квалификаторы по типам реальных методов.
    template<typename TSignature, bool IsConst, bool IsVolatile, meta::RefQual Ref>
    constexpr bool CheckMember = meta::FunctionTraits<TSignature>::Kind == meta::FuncKind::ClassMember &&
        meta::FunctionTraits<TSignature>::IsConst == IsConst &&
        meta::FunctionTraits<TSignature>::IsVolatile == IsVolatile &&
        meta::FunctionTraits<TSignature>::Ref == Ref &&
        std::is_same_v<typename meta::FunctionTraits<TSignature>::Class, Members>;

    static_assert(CheckMember<decltype(&Members::Plain), false, false, meta::RefQual::None>);
    static_assert(CheckMember<decltype(&Members::Const), true, false, meta::RefQual::None>);
    static_assert(CheckMember<decltype(&Members::Volatile), false, true, meta::RefQual::None>);
    static_assert(CheckMember<decltype(&Members::ConstVolatile), true, true, meta::RefQual::None>);
    static_assert(CheckMember<decltype(&Members::LValue), false, false, meta::RefQual::LValue>);
    static_assert(CheckMember<decltype(&Members::ConstLValue), true, false, meta::RefQual::LValue>);
    static_assert(CheckMember<decltype(&Members::VolatileLValue), false, true, meta::RefQual::LValue>);
    static_assert(CheckMember<decltype(&Members::ConstVolatileLValue), true, true, meta::RefQual::LValue>);
    static_assert(CheckMember<decltype(&Members::RValue), false, false, meta::RefQual::RValue>);
    static_assert(CheckMember<decltype(&Members::ConstRValue), true, false, meta::RefQual::RValue>);
    static_assert(CheckMember<decltype(&Members::VolatileRValue), false, true, meta::RefQual::RValue>);
    static_assert(CheckMember<decltype(&Members::ConstVolatileRValue), true, true, meta::RefQual::RValue>);

    template<typename TSignature, bool IsConst, bool IsVolatile, meta::RefQual Ref>
    constexpr bool CheckNoexceptMember = CheckMember<TSignature, IsConst, IsVolatile, Ref> &&
        meta::FunctionTraits<TSignature>::IsNoexcept;

    static_assert(CheckNoexceptMember<int(Members::*)() noexcept, false, false, meta::RefQual::None>);
    static_assert(CheckNoexceptMember<int(Members::*)() const noexcept, true, false, meta::RefQual::None>);
    static_assert(CheckNoexceptMember<int(Members::*)() volatile noexcept, false, true, meta::RefQual::None>);
    static_assert(CheckNoexceptMember<int(Members::*)() const volatile noexcept, true, true, meta::RefQual::None>);
    static_assert(CheckNoexceptMember<int(Members::*)() & noexcept, false, false, meta::RefQual::LValue>);
    static_assert(CheckNoexceptMember<int(Members::*)() const & noexcept, true, false, meta::RefQual::LValue>);
    static_assert(CheckNoexceptMember<int(Members::*)() volatile & noexcept, false, true, meta::RefQual::LValue>);
    static_assert(CheckNoexceptMember<int(Members::*)() const volatile & noexcept, true, true, meta::RefQual::LValue>);
    static_assert(CheckNoexceptMember<int(Members::*)() && noexcept, false, false, meta::RefQual::RValue>);
    static_assert(CheckNoexceptMember<int(Members::*)() const && noexcept, true, false, meta::RefQual::RValue>);
    static_assert(CheckNoexceptMember<int(Members::*)() volatile && noexcept, false, true, meta::RefQual::RValue>);
    static_assert(CheckNoexceptMember<int(Members::*)() const volatile && noexcept, true, true, meta::RefQual::RValue>);

    using Method = meta::FunctionTraits<decltype(&Members::Plain)>;
    static_assert(Method::ArgumentCount == 2);
    static_assert(std::is_same_v<Method::arg<0>::type, const int*>);
    static_assert(std::is_same_v<Method::arg_val<0>::type, const int>);
    static_assert(std::is_same_v<Method::arg_val<1>::type, double>);
    static_assert(!Method::IsNoexcept);
    static_assert(meta::FunctionTraits<decltype(&FreeFunction)>::IsNoexcept);
    static_assert(meta::FunctionTraits<decltype(FreeFunction)>::Kind == meta::FuncKind::CstyleFunc);
    static_assert(meta::FunctionTraits<Callable>::IsNoexcept);
    static_assert(meta::FunctionTraits<const Callable&>::Kind == meta::FuncKind::Functor);
    static_assert(meta::concepts::has_method_with_signature<decltype(&Members::Const), int(Members::*)() const>);
    static_assert(meta::concepts::has_static_function_with_signature<decltype(&FreeFunction), int(*)(int) noexcept>);
    static_assert(!meta::concepts::has_method<int>);
    static_assert(!meta::concepts::has_static_function<Callable>);
    static_assert(!meta::concepts::has_non_overloaded_call_op<Overloaded>);
    static_assert(meta::concepts::has_call_op_with_signature<Overloaded, int(int) const noexcept>);
    static_assert(!meta::concepts::has_call_op_with_signature<Overloaded, void(int) const>);
    static_assert(!meta::concepts::has_call_op_with_signature<int, int(int)>);
    using Explicit = meta::FunctionTraitsWithSignature<Overloaded, int(int) const noexcept>;
    static_assert(Explicit::Kind == meta::FuncKind::Functor && Explicit::IsConst && Explicit::IsNoexcept);
    static_assert(std::is_same_v<Explicit::Ret, int>);

    constexpr auto generic = [](auto value) { return value; };
    static_assert(!meta::concepts::has_non_overloaded_call_op<decltype(generic)>);
    static_assert(meta::concepts::has_call_op_with_signature<decltype(generic), int(int) const>);
    static_assert(meta::FunctionTraitsWithSignature<decltype(generic), int(int) const>::ArgumentCount == 1);
    constexpr auto mutableLambda = [value = 1]() mutable { return ++value; };
    static_assert(!meta::FunctionTraits<decltype(mutableLambda)>::IsConst);
    static_assert(meta::FunctionTraits<decltype(mutableLambda)>::ArgumentCount == 0);
    static_assert(!meta::FunctionTraits<decltype(mutableLambda)>::IsNoexcept);

    static_assert(meta::IF_value_c<true, 42, nullptr>::value == 42);
    static_assert(std::is_same_v<typename meta::IF_value_c<false, 42, nullptr>::value_type, std::nullptr_t>);
    static_assert(meta::concepts::IteratorOf<std::vector<int>::iterator, std::vector<int>>);
    static_assert(meta::concepts::IteratorOf<std::vector<int>::const_iterator, std::vector<int>>);
    static_assert(!meta::concepts::IteratorOf<int, std::vector<int>>);
    static_assert(meta::concepts::ErasableContainer<std::vector<int>>);
    static_assert(!meta::concepts::ErasableContainer<std::array<int, 2>>);
    static_assert(!meta::concepts::ErasableContainer<int>);
}

int main() {
    Callable callable;
    Overloaded overloaded;
    using Callback = meta::FunctionTraits<decltype(&FreeFunction)>::Signature;
    Callback callback = &FreeFunction;
    return callback(1) == 2 && callable(1) == 3 && overloaded(1) == 4 ? 0 : 1;
}