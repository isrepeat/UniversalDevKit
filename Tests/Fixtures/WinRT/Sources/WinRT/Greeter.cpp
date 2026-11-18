#include "Greeter.h"

#include <Core/Greeting.h>

#include "Greeter.g.cpp"

namespace winrt::HelloWorld::WinRT::implementation
{
    winrt::hstring Greeter::GetMessage()
    {
        return winrt::hstring{ ::HelloWorld::Core::MakeGreeting() };
    }
}