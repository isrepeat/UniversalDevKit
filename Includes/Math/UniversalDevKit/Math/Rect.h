#pragma once

namespace universaldevkit::math {
		namespace details {
			template <typename T>
			struct Rect {
				T left;
				T top;
				T right;
				T bottom;

				Rect()
					: left{ 0 }
					, top{ 0 }
					, right{ 0 }
					, bottom{ 0 } {
				}

				Rect(T left, T top, T right, T bottom)
					: left{ left }
					, top{ top }
					, right{ right }
					, bottom{ bottom } {
				}

				template <typename TTarget>
				explicit operator Rect<TTarget>() const {
					return Rect<TTarget>{
						static_cast<TTarget>(this->left),
							static_cast<TTarget>(this->top),
							static_cast<TTarget>(this->right),
							static_cast<TTarget>(this->bottom)
					};
				}
			};
		} // namespace details

	using Rect = details::Rect<unsigned int>;
	using Rect_f = details::Rect<float>;
}