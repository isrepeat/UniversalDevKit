#pragma once
#include <queue>

namespace universaldevkit::helpers::collection {

    template<typename T, typename TContainer = std::deque<T> >
    class iterable_queue : public std::queue<T, TContainer> {
    public:
        using iterator = typename TContainer::iterator;
        using const_iterator = typename TContainer::const_iterator;

        iterator begin() { return this->c.begin(); }
        iterator end() { return this->c.end(); }
        const_iterator begin() const { return this->c.begin(); }
        const_iterator end() const { return this->c.end(); }
    };
}