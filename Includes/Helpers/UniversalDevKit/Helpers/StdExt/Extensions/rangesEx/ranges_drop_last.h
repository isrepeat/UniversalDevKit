#pragma once
#include "../../../Meta/Concepts.h"
#include "../../Config.h"

#include "Tools.h"

#include <iterator>
#include <cstddef>
#include <utility>
#include <ranges>

namespace universaldevkit::helpers::stdext::extensions {
    namespace ranges {
        namespace views {
            //
            // ░ drop_last
            // ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
            //
            // ░ drop_last_view
            //
            template <typename TView>
            __requires_expr(std::ranges::forward_range<TView> && std::ranges::view<TView>)
            class drop_last_view : public std::ranges::view_interface<drop_last_view<TView>> {
            public:
                drop_last_view() = default;

                constexpr drop_last_view(TView baseView, std::size_t countToDrop)
                    : baseView{std::move(baseView)}
                    , countToDrop{countToDrop} {
                }

                // A leading iterator keeps n elements ahead without measuring the range.
                // Finite unsized and infinite forward ranges are both supported.
                class iterator {
                public:
                    using iterator_concept = std::forward_iterator_tag;
                    using iterator_category = std::forward_iterator_tag;
                    using difference_type = std::ranges::range_difference_t<TView>;
                    using value_type = std::ranges::range_value_t<TView>;

                    iterator() = default;

                    iterator(std::ranges::iterator_t<TView> current, std::ranges::sentinel_t<TView> sentinel, std::size_t countToDrop)
                        : current{current}
                        , leading{current}
                        , sentinel{sentinel} {
                        while (countToDrop != 0 && this->leading != this->sentinel) {
                            ++this->leading;
                            --countToDrop;
                        }
                    }

                    decltype(auto) operator*() const {
                        return *this->current;
                    }

                    iterator& operator++() {
                        ++this->current;
                        ++this->leading;
                        return *this;
                    }

                    iterator operator++(int) {
                        auto copy = *this;
                        ++*this;
                        return copy;
                    }

                    bool operator==(const iterator& other) const {
                        return this->current == other.current;
                    }

                    bool operator==(std::default_sentinel_t) const {
                        return this->leading == this->sentinel;
                    }

                private:
                    std::ranges::iterator_t<TView> current{};
                    std::ranges::iterator_t<TView> leading{};
                    std::ranges::sentinel_t<TView> sentinel{};
                };

                constexpr auto begin() {
                    return iterator{std::ranges::begin(this->baseView), std::ranges::end(this->baseView), this->countToDrop};
                }

                constexpr auto end() {
                    return std::default_sentinel;
                }

                // Recompute on each call; the source may change between traversals.
                constexpr auto size()
                    requires std::ranges::sized_range<TView>
                {
                    const auto total = std::ranges::size(this->baseView);
                    return total > this->countToDrop ? total - this->countToDrop : decltype(total){0};
                }

            private:
                TView baseView;
                std::size_t countToDrop{0};
            };

            //
            // ░ drop_last_closure
            //
            struct drop_last_closure {
            public:
                std::size_t countToDrop{0};

            public:
                template <typename TRange>
                __requires_expr(std::ranges::forward_range<TRange> && std::ranges::viewable_range<TRange>)
                friend auto operator|(TRange&& range, const drop_last_closure& self) {
                    using View_t = ranges::tools::view_of_t<TRange>;
                    return drop_last_view<View_t>{views::tools::as_view(std::forward<TRange>(range)), self.countToDrop};
                }
            };

            //
            // ░ drop_last_fn
            //
            struct drop_last_fn {
                constexpr auto operator()(std::size_t n) const {
                    return drop_last_closure{.countToDrop = n};
                }

                template <typename TRange>
                __requires_expr(std::ranges::forward_range<TRange> && std::ranges::viewable_range<TRange>)
                constexpr auto operator()(TRange&& range, std::size_t n) const {
                    using View_t = ranges::tools::view_of_t<TRange>;
                    return drop_last_view<View_t>{views::tools::as_view(std::forward<TRange>(range)), n};
                }
            };

            inline constexpr drop_last_fn drop_last{};
        }
    } // namespace ranges

    namespace views = ranges::views;
}