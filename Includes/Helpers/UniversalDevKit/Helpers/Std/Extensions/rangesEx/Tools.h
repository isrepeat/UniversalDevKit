#pragma once
#include <UniversalDevKit/Helpers/Meta/Concepts.h>
#include <UniversalDevKit/Helpers/Std/Config.h>

#include <algorithm>
#include <utility>
#include <ranges>

namespace STD_EXT_NS {
	namespace ranges {
		namespace tools {
			//
			// ░ view_of
			// ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
			// Type alias that obtains the view type for an arbitrary viewable_range.
			//
			template <class TRange>
			using view_of_t = decltype(::std::ranges::views::all(::std::declval<TRange>()));
		}

		namespace views {
			namespace tools {
				//
				// ░ as_view
				// ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
				// Converts any viewable_range into a view.
				// This is equivalent to std::ranges::views::all, with a more explicit name.
				//
				// std::ranges::views::all converts any viewable object into a view:
				//   - an existing view is returned as-is;
				//   - an lvalue container is wrapped in ref_view;
				//   - an rvalue viewable_range is materialized as a compatible view.
				//
				template <class TRange>
				constexpr auto as_view(TRange&& r) -> decltype(::std::ranges::views::all(::std::forward<TRange>(r))) {
					return ::std::ranges::views::all(::std::forward<TRange>(r));
				}
			}
		}
	}
}