#pragma once
#include "ExtraGreeter.g.h"

namespace winrt::HelloWorld::ExtraWinRT::implementation
{
    struct ExtraGreeter : ExtraGreeterT<ExtraGreeter>
    {
        ExtraGreeter() = default;
        winrt::hstring GetMessage();
    };
}

namespace winrt::HelloWorld::ExtraWinRT::factory_implementation
{
    struct ExtraGreeter : ExtraGreeterT<ExtraGreeter, implementation::ExtraGreeter>
    {
    };
}