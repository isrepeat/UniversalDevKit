#pragma once
#include <UniversalDevKit/Helpers/Meta/Concepts.h>
#include <UniversalDevKit/Helpers/Std/Config.h>

#include "Tools.h"

#include <type_traits>
#include <algorithm>
#include <iterator>
#include <optional>
#include <utility>
#include <ranges>

namespace STD_EXT_NS {
	namespace ranges {
		namespace views {
			//
			// ░ concat
			// ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
			//
			// Purpose:
			//   Lazily concatenate two arbitrary viewable_range objects so callers can write:
			//     rng1 | std::ex::ranges::views::concat(rng2)
			//   The adaptor does not copy elements. After consuming the first range, it continues
			//   with the second. concat_view owns both source views, keeping its iterators valid.
			//
			// Constraints:
			//   - Both arguments are input_range views that can be stored by value.
			//   - Their reference types satisfy common_reference_with, giving concat_view one
			//     reference type compatible with both source ranges.
			//
			// Implementation notes:
			//   - The iterator category is input_iterator; forward_range support can be added later.
			//   - The range uses default_sentinel and reaches the end only after the second range ends.
			//   - If the first range is empty, begin() starts directly in the second range.
			//
			// ░ concat_view
			//
			template <
				typename TView1,
				typename TView2
			>
			__requires_expr(
				::std::ranges::input_range<TView1>&&
				::std::ranges::input_range<TView2>&&
				::std::ranges::view<TView1>&&
				::std::ranges::view<TView2>&&
				::std::common_reference_with<
				::std::ranges::range_reference_t<TView1>,
				::std::ranges::range_reference_t<TView2>
				>
			) class concat_view : public ::std::ranges::view_interface<concat_view<TView1, TView2>> {
			public:
				// Stores a parent pointer for view access and the current iteration state:
				//   - inFirst          : true while iterating over the first range;
				//   - iterFirstOpt     : active first-range iterator when inFirst is true;
				//   - iterSecondOpt    : active second-range iterator when inFirst is false.
				//
				// Lazy transition:
				//   - incrementing in the first range advances iterFirst and switches to begin(second)
				//     when end(first) is reached;
				//   - incrementing in the second range advances iterSecond.
				//
				class iterator {
				public:
					// Standard iterator type aliases.
					using iterator_concept = ::std::input_iterator_tag;
					using iterator_category = ::std::input_iterator_tag;
					using difference_type = ::std::ptrdiff_t;
					using reference = ::std::common_reference_t<
						::std::ranges::range_reference_t<TView1>,
						::std::ranges::range_reference_t<TView2>
					>;
					using value_type = ::std::common_type_t<
						::std::ranges::range_value_t<TView1>,
						::std::ranges::range_value_t<TView2>
					>;

					using It1_t = ::std::ranges::iterator_t<TView1>;
					using It2_t = ::std::ranges::iterator_t<TView2>;

					iterator() = default;

					explicit iterator(
						concat_view* parentPtr,
						bool isInFirst,
						::std::optional<It1_t> iterFirstOptInit,
						::std::optional<It2_t> iterSecondOptInit
					)
						: parent{ parentPtr }
						, inFirst{ isInFirst }
						, iterFirstOpt{ ::std::move(iterFirstOptInit) }
						, iterSecondOpt{ ::std::move(iterSecondOptInit) } {
					}

					reference operator*() const {
						// Dereference the active iterator from either the first or second range.
						if (this->inFirst) {
							return **this->iterFirstOpt;
						}
						else {
							return **this->iterSecondOpt;
						}
					}

					iterator& operator++() {
						// Advance the active iterator. Reaching the end of the first range
						// switches iteration to the beginning of the second range.
						if (this->inFirst) {
							auto& it1 = *this->iterFirstOpt;
							++it1;

							if (it1 == ::std::ranges::end(this->parent->viewFirst)) {
								this->inFirst = false;
								this->iterSecondOpt = ::std::ranges::begin(this->parent->viewSecond);
							}
						}
						else {
							auto& it2 = *this->iterSecondOpt;
							++it2;
						}

						return *this;
					}

					iterator operator++(int) {
						auto iteratorCopy = *this;
						++(*this);
						return iteratorCopy;
					}

					// Member comparison form: iterator == default_sentinel.
					bool operator==(::std::default_sentinel_t) const {
						// The concatenated range ends only after the second range reaches its end.
						if (this->inFirst) {
							return false;
						}

						return *(this->iterSecondOpt) == ::std::ranges::end(this->parent->viewSecond);
					}

					// Symmetric free-function form: default_sentinel == iterator.
					friend bool operator==(::std::default_sentinel_t s, const iterator& it) {
						return it == s;
					}

				private:
					concat_view* parent;
					bool inFirst;
					::std::optional<It1_t> iterFirstOpt;
					::std::optional<It2_t> iterSecondOpt;
				}; // class iterator

				friend class iterator; // Grants access to viewFirst and viewSecond.


				concat_view() = default;

				constexpr concat_view(
					TView1 v1,
					TView2 v2
				)
					: viewFirst{ ::std::move(v1) }
					, viewSecond{ ::std::move(v2) } {
				}

				iterator begin() {
					auto it1 = ::std::ranges::begin(this->viewFirst);
					auto e1 = ::std::ranges::end(this->viewFirst);

					// Start in the second range when the first is empty; otherwise start in the first.
					if (it1 == e1) {
						auto it2 = ::std::ranges::begin(this->viewSecond);

						return iterator{
							this,
							false,
							::std::nullopt,
							::std::optional{ it2 }
						};
					}
					else {
						return iterator{
							this,
							true,
							::std::optional{ it1 },
							::std::nullopt
						};
					}
				}

				::std::default_sentinel_t end() {
					return ::std::default_sentinel;
				}

			private:
				// Store both views by value to control their lifetime for the entire iteration.
				TView1 viewFirst;
				TView2 viewSecond;
			};


			//
			// ░ concat_losure
			//
			// Closure object used by pipeline syntax.
			//   v1 | concat(v2)
			// Store the second operand as a view; operator| supplies the first operand.
			// Keeping the second view inside the closure guarantees its lifetime.
			//
			template <typename TRange2>
			__requires_expr(
				::std::ranges::viewable_range<TRange2>
			) struct concat_closure {
				ranges::tools::view_of_t<TRange2> viewSecond;

				template <typename TRange1>
				__requires_expr(
					::std::ranges::viewable_range<TRange1>
				) friend auto operator|(
					TRange1&& viewFirst,
					const concat_closure& closure
					) {
					using View1_t = ranges::tools::view_of_t<TRange1>;
					using View2_t = ranges::tools::view_of_t<TRange2>;
					return concat_view<View1_t, View2_t>{
						views::tools::as_view(::std::forward<TRange1>(viewFirst)),
							closure.viewSecond
					};
				}
			};


			//
			// ░ concat_fn
			//
			struct concat_fn {
				template <typename TRange2>
				__requires_expr(
					::std::ranges::viewable_range<TRange2>
				) constexpr auto operator()(
					TRange2&& r2
					) const {
					return concat_closure<TRange2>{
						views::tools::as_view(::std::forward<TRange2>(r2))
					};
				}

				template <
					typename TRange1,
					typename TRange2
				>
				__requires_expr(
					::std::ranges::viewable_range<TRange1>&&
					::std::ranges::viewable_range<TRange2>
				) constexpr auto operator()(
					TRange1&& r1,
					TRange2&& r2
					) const {
					using View1_t = ranges::tools::view_of_t<TRange1>;
					using View2_t = ranges::tools::view_of_t<TRange2>;
					return concat_view<View1_t, View2_t>{
						views::tools::as_view(::std::forward<TRange1>(r1)),
							views::tools::as_view(::std::forward<TRange2>(r2))
					};
				}
			};

			inline constexpr concat_fn concat{};
		}
	}

	namespace views = ranges::views;
}