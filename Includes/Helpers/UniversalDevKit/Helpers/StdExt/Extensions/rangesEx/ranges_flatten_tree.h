#pragma once
#include "../../../Meta/Concepts.h"
#include "../../Config.h"

#include "Tools.h"

#include <type_traits>
#include <functional>
#include <algorithm>
#include <iterator>
#include <optional>
#include <utility>
#include <memory>
#include <ranges>
#include <vector>

namespace universaldevkit::helpers::stdext::extensions {
    namespace ranges {
        namespace views {
            namespace concepts {
                template <typename TGetChildrenFn, typename TNode>
                concept children_fn_valid = std::copy_constructible<TNode> && requires(TGetChildrenFn& getChildrenFn, TNode& node) {
                    { std::invoke(getChildrenFn, node) } -> std::ranges::input_range;
                    requires std::same_as<std::ranges::range_value_t<std::invoke_result_t<TGetChildrenFn&, TNode&>>, TNode>;
                    requires std::constructible_from<TNode, std::ranges::range_reference_t<std::invoke_result_t<TGetChildrenFn&, TNode&>>>;
                };

                template <typename TView, typename TGetChildrenFn>
                concept tree_source = std::ranges::view<TView> && std::ranges::input_range<TView> &&
                    children_fn_valid<TGetChildrenFn, std::ranges::range_value_t<TView>> &&
                    std::constructible_from<std::ranges::range_value_t<TView>, std::ranges::range_reference_t<TView>>;
            } // namespace concepts

            //
            // ░ flatten_tree
            // ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
            //
            // Finite, acyclic trees; copyable node values or handles.
            // Only nullable nodes are skipped. Numeric zero and false remain valid nodes.
            // The view owns its callback and must outlive its iterators.
            //
            // ░ flatten_tree_view
            //
            template <typename TView, typename TGetChildrenFn>
            __requires_expr(concepts::tree_source<TView, TGetChildrenFn>)
            class flatten_tree_view : public std::ranges::view_interface<flatten_tree_view<TView, TGetChildrenFn>> {
            public:
                using Node_t = std::ranges::range_value_t<TView>;

            private:
                static bool IsNull(const Node_t& node) {
                    if constexpr (requires { { node == nullptr } -> std::convertible_to<bool>; }) {
                        return node == nullptr;
                    }
                    else {
                        return false;
                    }
                }

            public:
                class iterator {
                public:
                    using iterator_concept = std::input_iterator_tag;
                    using iterator_category = std::input_iterator_tag;
                    using difference_type = std::ptrdiff_t;
                    using value_type = Node_t;
                    using reference = const Node_t&;

                    iterator() = default;

                    iterator(TGetChildrenFn* getChildrenFn, std::vector<Node_t> roots)
                        : getChildrenFn{getChildrenFn}
                        , stack{std::move(roots)} {
                        std::reverse(this->stack.begin(), this->stack.end());
                        this->advance_to_next();
                    }

                    reference operator*() const {
                        return *this->currentNode;
                    }

                    const Node_t* operator->() const {
                        return std::addressof(*this->currentNode);
                    }

                    iterator& operator++() {
                        this->advance_to_next();
                        return *this;
                    }

                    void operator++(int) {
                        ++*this;
                    }

                    bool operator==(std::default_sentinel_t) const {
                        return !this->currentNode;
                    }

                private:
                    void advance_to_next() {
                        if (this->stack.empty()) {
                            this->currentNode.reset();
                            return;
                        }

                        // Emit the parent, then queue children for left-to-right preorder traversal.
                        this->currentNode.emplace(std::move(this->stack.back()));
                        this->stack.pop_back();
                        auto&& children = std::invoke(*this->getChildrenFn, *this->currentNode);
                        std::vector<Node_t> pending;
                        for (auto&& child : children) {
                            if (!IsNull(child)) {
                                pending.push_back(child);
                            }
                        }
                        for (auto current = pending.rbegin(); current != pending.rend(); ++current) {
                            this->stack.push_back(std::move(*current));
                        }
                    }

                    TGetChildrenFn* getChildrenFn{nullptr};
                    std::vector<Node_t> stack;
                    std::optional<Node_t> currentNode;
                };

                flatten_tree_view(TView rootsView, TGetChildrenFn getChildrenFn)
                    : rootsView{std::move(rootsView)}
                    , getChildrenFn{std::move(getChildrenFn)} {
                }

                auto begin() {
                    std::vector<Node_t> roots;
                    for (auto&& root : this->rootsView) {
                        if (!IsNull(root)) {
                            roots.push_back(root);
                        }
                    }
                    return iterator{std::addressof(this->getChildrenFn), std::move(roots)};
                }

                auto end() {
                    return std::default_sentinel;
                }

            private:
                TView rootsView;
                TGetChildrenFn getChildrenFn;
            };

            //
            // ░ flatten_tree_closure
            //
            template <typename TGetChildrenFn>
            struct flatten_tree_closure {
                TGetChildrenFn getChildrenFn;

                template <typename TRange>
                __requires_expr(
                    std::ranges::viewable_range<TRange> &&
                    concepts::tree_source<ranges::tools::view_of_t<TRange>, TGetChildrenFn> &&
                    std::copy_constructible<TGetChildrenFn>
                )
                friend auto operator|(TRange&& roots, const flatten_tree_closure& self) {
                    return flatten_tree_view<ranges::tools::view_of_t<TRange>, TGetChildrenFn>{
                        views::tools::as_view(std::forward<TRange>(roots)),
                        self.getChildrenFn
                    };
                }

                template <typename TRange>
                __requires_expr(
                    std::ranges::viewable_range<TRange> &&
                    concepts::tree_source<ranges::tools::view_of_t<TRange>, TGetChildrenFn>
                )
                friend auto operator|(TRange&& roots, flatten_tree_closure&& self) {
                    return flatten_tree_view<ranges::tools::view_of_t<TRange>, TGetChildrenFn>{
                        views::tools::as_view(std::forward<TRange>(roots)),
                        std::move(self.getChildrenFn)
                    };
                }
            };

            //
            // ░ flatten_tree_fn
            //
            struct flatten_tree_fn {
                template <typename TRange, typename TGetChildrenFn>
                __requires_expr(
                    std::ranges::viewable_range<TRange> &&
                    concepts::tree_source<ranges::tools::view_of_t<TRange>, std::decay_t<TGetChildrenFn>> &&
                    std::constructible_from<std::decay_t<TGetChildrenFn>, TGetChildrenFn>
                )
                constexpr auto operator()(TRange&& roots, TGetChildrenFn&& getChildrenFn) const {
                    return flatten_tree_view<ranges::tools::view_of_t<TRange>, std::decay_t<TGetChildrenFn>>{
                        views::tools::as_view(std::forward<TRange>(roots)),
                        std::forward<TGetChildrenFn>(getChildrenFn)
                    };
                }

                template <typename TGetChildrenFn>
                constexpr auto operator()(TGetChildrenFn&& getChildrenFn) const {
                    return flatten_tree_closure<std::decay_t<TGetChildrenFn>>{std::forward<TGetChildrenFn>(getChildrenFn)};
                }
            };

            inline constexpr flatten_tree_fn flatten_tree{};
        }
    } // namespace ranges

    namespace views = ranges::views;
}