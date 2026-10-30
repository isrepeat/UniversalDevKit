#pragma once
#include "../../../Meta/Concepts.h"
#include "../../Config.h"

#include <type_traits>
#include <iterator>
#include <utility>
#include <ranges>

namespace universaldevkit::helpers::stdext::extensions {
    namespace ranges {
        namespace views {
            namespace concepts {
                template <typename TContainer, typename TRange, bool Move>
                concept collectable_range = std::ranges::input_range<TRange> && std::default_initializable<TContainer> &&
                    std::constructible_from<
                        typename TContainer::value_type,
                        std::conditional_t<Move, std::ranges::range_rvalue_reference_t<TRange>, std::ranges::range_reference_t<TRange>>
                    > && requires(
                        TContainer& container,
                        std::conditional_t<Move, std::ranges::range_rvalue_reference_t<TRange>, std::ranges::range_reference_t<TRange>> element
                    ) {
                        container.insert(container.end(), std::forward<decltype(element)>(element));
                    };
            } // namespace concepts

            //
            // ░ to
            // ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
            //
            // Copy/reference semantics by default, including for rvalue containers.
            // Use to<Container>(move_elements) to explicitly consume source elements.
            struct move_elements_t {};
            inline constexpr move_elements_t move_elements{};

            //
            // ░ to_closure
            //
            template <typename TContainer, bool Move = false>
            struct to_closure {
                template <typename TRange>
                __requires_expr(concepts::collectable_range<TContainer, TRange, Move>)
                friend auto operator|(TRange&& range, to_closure) {
                    TContainer container;
                    if constexpr (std::ranges::sized_range<TRange> && requires { container.reserve(std::ranges::size(range)); }) {
                        container.reserve(std::ranges::size(range));
                    }

                    auto output = std::inserter(container, container.end());
                    auto current = std::ranges::begin(range);
                    const auto sentinel = std::ranges::end(range);
                    for (; current != sentinel; ++current) {
                        if constexpr (Move) {
                            *output = std::ranges::iter_move(current);
                        }
                        else {
                            *output = *current;
                        }
                        ++output;
                    }
                    return container;
                }
            };

            //
            // ░ to_fn
            //
            template <typename TContainer>
            struct to_fn {
                constexpr auto operator()() const noexcept {
                    return to_closure<TContainer>{};
                }

                constexpr auto operator()(move_elements_t) const noexcept {
                    return to_closure<TContainer, true>{};
                }
            };

            template <typename TContainer>
            inline constexpr to_fn<TContainer> to{};
        }
    } // namespace ranges

    namespace views = ranges::views;
}