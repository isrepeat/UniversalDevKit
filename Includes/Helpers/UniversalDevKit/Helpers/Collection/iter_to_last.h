#pragma once
#include <stdexcept>
#include <iterator>

namespace universaldevkit::helpers::collection {

    template<typename TContainer>
    auto iter_to_last(TContainer&& cont) {
        auto last = std::end(cont);
        if (last == std::begin(cont)) {
            throw std::invalid_argument("container is empty");
        }
        return std::prev(last);
    }
}