#pragma once
#include "../../../Meta/Concepts.h"
#include "../../Config.h"

#include <algorithm>
#include <iterator>
#include <ranges>

namespace universaldevkit::helpers::stdext::extensions {
    namespace ranges {
        namespace views {
            //
            // ░ to
            // ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
            //
            // ░ to_closure
            //
            template <typename TContainer>
            struct to_closure {
                template <typename TRange>
                __requires_expr(std::ranges::input_range<TRange>)
                friend auto operator|(
                    TRange&& range, to_closure /*self*/
                ) {
                    TContainer container;

                    if constexpr (requires { container.reserve(std::ranges::size(range)); }) {
                        container.reserve(std::ranges::size(range));
                    }

                    // Works uniformly for map, set, and similar containers.
                    // inserter is slightly slower for vector, but is portable across containers.
                    std::ranges::copy(range, std::inserter(container, container.end()));

                    return container;
                }
            };

            //
            // ░ to_fn
            //
            template <typename TContainer>
            struct to_fn {
            public:
                constexpr auto operator()() const noexcept {
                    return to_closure<TContainer>{};
                }
            };

            template <typename TContainer>
            inline constexpr to_fn<TContainer> to{};
        }
    } // namespace ranges

    namespace views = ranges::views;
}