#pragma once
#include "../Meta/Utilities/ValueExtractor.h"
#include "../Meta/Concepts.h"

#include <functional>
#include <algorithm>
#include <concepts>
#include <iterator>
#include <utility>
#include <vector>
#include <set>

namespace universaldevkit::helpers::collection {
    template<
        typename TIter,
        typename TContainer,
        typename TPredicate
    >
    __requires_expr(
        meta::concepts::IteratorOf<TIter, TContainer>&&
        meta::concepts::ErasableContainer<TContainer>
    ) TContainer Extract(
        TContainer& collection,
        TIter firstIt,
        TIter lastIt,
        TPredicate&& predicate
    ) {
        // Keep selected values intact before moving them to the result.
        auto firstRemovedIt = std::stable_partition(firstIt, lastIt, [&](const auto& value) {
            return !std::invoke(predicate, value);
        });

        // Move selected values and erase their original range.
        TContainer extractedItems;

        extractedItems.insert(
            extractedItems.end(),
            std::make_move_iterator(firstRemovedIt),
            std::make_move_iterator(lastIt)
        );

        collection.erase(firstRemovedIt, lastIt);
        return extractedItems;
    }

    template<
        typename TContainer,
        typename TPredicate
    >
    __requires_expr(
        meta::concepts::ErasableContainer<TContainer>
    ) TContainer Extract(TContainer& collection, TPredicate&& predicate) {
        return Extract(
            collection,
            collection.begin(),
            collection.end(),
            std::forward<TPredicate>(predicate)
        );
    }

    class Set {
    public:
        template<typename T, typename... TArgs>
        static bool IsHasIntersection(
            const std::set<T, TArgs...>& a,
            const std::set<T, TArgs...>& b
        ) {
            if (a.empty() || b.empty()) {
                return false;
            }

            auto itA = a.begin();
            auto itB = b.begin();

            while (itA != a.end() && itB != b.end()) {
                const auto& valA = meta::utilities::ValueExtractor::From(itA);
                const auto& valB = meta::utilities::ValueExtractor::From(itB);

                if (valA < valB) {
                    ++itA;
                }
                else if (valB < valA) {
                    ++itB;
                }
                else {
                    return true;
                }
            }

            return false;
        }
    };
}