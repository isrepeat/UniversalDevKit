#pragma once
#include <concepts>

// Keep multiline constraints readable with the Visual Studio formatter.
#define __requires_expr(...) requires (__VA_ARGS__)

namespace universaldevkit::meta::concepts {
    template<typename T>
    concept Dereferenceable = requires(const T & value) {
        *value;
    };

    template<typename TIterator, typename TContainer>
    concept IteratorOf = std::same_as<TIterator, typename TContainer::iterator> ||
        std::same_as<TIterator, typename TContainer::const_iterator>;

    template<typename TContainer>
    concept ErasableContainer = requires(TContainer & container, typename TContainer::iterator first, typename TContainer::iterator last) {
        { container.erase(first, last) } -> std::same_as<typename TContainer::iterator>;
    };
}