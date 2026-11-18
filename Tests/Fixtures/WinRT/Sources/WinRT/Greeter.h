#pragma once
#include "Greeter.g.h"

namespace winrt::HelloWorld::WinRT::implementation
{
    struct Greeter : GreeterT<Greeter>
    {
        Greeter() = default;
        winrt::hstring GetMessage();
    };
}

namespace winrt::HelloWorld::WinRT::factory_implementation
{
    struct Greeter : GreeterT<Greeter, implementation::Greeter>
    {
    };
}