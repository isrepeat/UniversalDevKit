#include "ExtraGreeter.h"

#include <Core/Greeting.h>

#include "ExtraGreeter.g.cpp"

namespace winrt::HelloWorld::ExtraWinRT::implementation
{
    winrt::hstring ExtraGreeter::GetMessage()
    {
        return winrt::hstring{ ::HelloWorld::Core::MakeGreeting() };
    }
}