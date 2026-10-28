#pragma once
#include "../../../Meta/Concepts.h"
#include "../../Config.h"

#include "Tools.h"

#include <type_traits>
#include <algorithm>
#include <iterator>
#include <optional>
#include <utility>
#include <ranges>
#include <vector>

namespace universaldevkit::helpers::stdext::extensions {
    namespace ranges {
        namespace views {
            namespace details {
                namespace concepts {
                    template <typename TGetChildrenFn, typename TNode>
                    concept children_fn_return_input_range = requires(TGetChildrenFn getChildrenFn, TNode node) {
                        { getChildrenFn(node) } -> std::ranges::input_range;
                    };

                    // TGetChildrenFn accepts a TNode and returns an input_range of child nodes.
                    template <typename TGetChildrenFn, typename TNode>
                    concept children_fn_valid = std::same_as<std::ranges::range_value_t<std::invoke_result_t<TGetChildrenFn, TNode>>, TNode> &&
                                                children_fn_return_input_range<TGetChildrenFn, TNode>;
                }
            } // namespace details

            //
            // ░ flatten_tree
            // ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
            //
            // ░ flatten_tree_view
            //
            // Why does this class store a decayed callback type (TGetChildrenFn_decayed_t)?
            // 1) Without normalization, perfect forwarding may deduce TGetChildrenFn as a reference,
            //    such as const Lambda&. A pointer to that type would become an illegal pointer to a
            //    reference. decay_t ensures that the view owns a value and the iterator stores a
            //    regular pointer to that value.
            // 2) Value storage provides a stable lifetime and avoids dangling references regardless
            //    of whether the original callback was an lvalue, rvalue, or const object.
            // 3) A canonical internal type reduces template instantiations and produces clearer
            //    compiler diagnostics independent of the input cv/ref qualifiers.
            // 4) remove_cvref_t would be enough for most lambdas and function objects, but decay_t
            //    also converts functions to function pointers and arrays to element pointers.
            template <typename TView, typename TGetChildrenFn>
            __requires_expr(std::ranges::view<TView>)
            class flatten_tree_view : public std::ranges::view_interface<flatten_tree_view<TView, TGetChildrenFn>> {
            public:
                using Node_t = std::ranges::range_value_t<TView>;
                using TGetChildrenFn_decayed_t = std::decay_t<TGetChildrenFn>; // Normalize the callback type.

                class iterator {
                public:
                    // Standard iterator type aliases.
                    using iterator_concept = std::input_iterator_tag;
                    using iterator_category = std::input_iterator_tag;
                    using difference_type = std::ptrdiff_t;
                    using value_type = Node_t;
                    using reference = Node_t;

                public:
                    iterator() = default;

                    explicit iterator(const TGetChildrenFn_decayed_t* getChildrenFnPtr, std::vector<Node_t>&& roots)
                        : getChildrenFnPtr{getChildrenFnPtr}, stack{std::move(roots)} {
                        // The stack initially contains roots in their original order.
                        // Reverse them so LIFO traversal still visits roots from left to right.
                        std::reverse(this->stack.begin(), this->stack.end());
                        this->advance_to_next();
                    }

                    reference operator*() const {
                        return this->currentNode;
                    }

                    const Node_t* operator->() const {
                        return std::addressof(this->currentNode);
                    }

                    iterator& operator++() {
                        this->advance_to_next();
                        return *this;
                    }

                    void operator++(int) {
                        ++(*this);
                    }

                    bool operator==(std::default_sentinel_t) const {
                        return this->atEnd;
                    }

                    friend bool operator==(std::default_sentinel_t s, const iterator& it) {
                        return it == s;
                    }

                private:
                    void advance_to_next() {
                        // Implements a left-to-right pre-order tree traversal.
                        // For example, given this tree:
                        // Root
                        //  ├─ A
                        //  │  ├─ A1
                        //  │  └─ A2
                        //  └─ B
                        //     └─ B1
                        //
                        // the traversal result is [Root, A, A1, A2, B, B1, B2].

                        if (this->stack.empty()) {
                            this->atEnd = true;
                            return;
                        }

                        this->currentNode = std::move(this->stack.back());
                        this->stack.pop_back();

                        auto currentNodeChildrenView = (*this->getChildrenFnPtr)(this->currentNode);

                        // Collect child nodes from left to right.
                        std::vector<Node_t> currentNodeChildren;
                        for (auto&& child : currentNodeChildrenView) {
                            if (static_cast<bool>(child)) {
                                currentNodeChildren.push_back(child);
                            }
                        }

                        // Push them in reverse order (right to left), so LIFO extraction
                        // visits them from left to right.
                        //
                        // For example, if stack = [B, A*, Root*] == [B], after this loop it
                        // becomes [B, A*, Root*, A2, A1] == [B, A2, A1].
                        // An asterisk marks an item that has already been visited and removed.
                        for (auto it = currentNodeChildren.rbegin(); it != currentNodeChildren.rend(); ++it) {
                            this->stack.push_back(std::move(*it));
                        }
                    }

                private:
                    const TGetChildrenFn_decayed_t* getChildrenFnPtr{nullptr};
                    std::vector<Node_t> stack; // LIFO stack used for left-to-right traversal.
                    Node_t currentNode;
                    bool atEnd = false;
                }; // class iterator

                flatten_tree_view(TView rootsView, const TGetChildrenFn_decayed_t& getChildrenFn)
                    : rootsView{std::move(rootsView)}, getChildrenFn{getChildrenFn} {
                    static_assert(
                        details::concepts::children_fn_valid<TGetChildrenFn_decayed_t, Node_t>,
                        "TGetChildrenFn must return an input_range with range_value_t == Node_t"
                    );
                }

                auto begin() {
                    std::vector<Node_t> roots;

                    // Collect root nodes from left to right.
                    for (auto&& r : this->rootsView) {
                        if (static_cast<bool>(r)) {
                            roots.push_back(r);
                        }
                    }

                    return iterator{std::addressof(this->getChildrenFn), std::move(roots)};
                }

                auto end() {
                    return std::default_sentinel;
                }

            private:
                TView rootsView;
                TGetChildrenFn_decayed_t getChildrenFn;
            };

            //
            // ░ flatten_tree_closure
            //
            template <typename TGetChildrenFn>
            struct flatten_tree_closure {
            public:
                TGetChildrenFn getChildrenFn;

            public:
                template <typename TRange>
                __requires_expr(std::ranges::viewable_range<TRange>)
                friend auto operator|(TRange&& roots, const flatten_tree_closure& self) {
                    using TView = ranges::tools::view_of_t<TRange>;
                    using Node_t = std::ranges::range_value_t<TView>;

                    static_assert(
                        details::concepts::children_fn_valid<TGetChildrenFn, Node_t>,
                        "TGetChildrenFn(node) must return an input_range with range_value_t == Node_t"
                    );

                    return flatten_tree_view<TView, TGetChildrenFn>{views::tools::as_view(std::forward<TRange>(roots)), self.getChildrenFn};
                }
            };

            //
            // ░ flatten_tree_fn
            //
            struct flatten_tree_fn {
            public:
                template <typename TRange, typename TGetChildrenFn>
                __requires_expr(std::ranges::viewable_range<TRange>)
                constexpr auto operator()(TRange&& roots, TGetChildrenFn&& getChildrenFn) const {
                    using TView = ranges::tools::view_of_t<TRange>;
                    using Node_t = std::ranges::range_value_t<TView>;

                    static_assert(
                        details::concepts::children_fn_valid<TGetChildrenFn, Node_t>,
                        "get_children(node) must return an input_range with range_value_t == Node_t"
                    );

                    return flatten_tree_view<TView, TGetChildrenFn>{
                        views::tools::as_view(std::forward<TRange>(roots)), std::forward<TGetChildrenFn>(getChildrenFn)
                    };
                }

                template <typename TGetChildrenFn>
                constexpr auto operator()(TGetChildrenFn&& getChildrenFn) const {
                    return flatten_tree_closure<TGetChildrenFn>{.getChildrenFn = std::forward<TGetChildrenFn>(getChildrenFn)};
                }
            };

            inline constexpr flatten_tree_fn flatten_tree{};
        }
    } // namespace ranges

    namespace views = ranges::views;
}

//
// ░ Export concepts
// ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
//
namespace universaldevkit::helpers {
    namespace meta {
        namespace concepts {
            // ...
        }
    }
}