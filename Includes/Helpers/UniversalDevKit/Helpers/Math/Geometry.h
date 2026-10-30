#pragma once
#include "Rect.h"
#include "Size.h"

#include <algorithm>
#include <stdexcept>
#include <limits>
#include <cmath>

namespace universaldevkit::helpers::math {
    template<typename T>
    struct Bounds {
        T x{};
        T y{};
        T width{};
        T height{};
        bool operator==(const Bounds&) const = default;
    };

    template<typename T>
    struct Insets {
        T left{};
        T top{};
        T right{};
        T bottom{};
        constexpr T Horizontal() const { return this->left + this->right; }
        constexpr T Vertical() const { return this->top + this->bottom; }
        bool operator==(const Insets&) const = default;
    };

    using Bounds_f = Bounds<float>;
    using Insets_f = Insets<float>;

    class Geometry final {
    public:
        static constexpr Bounds_f FromEdges(const Rect_f& rect) {
            return {rect.left, rect.top, rect.right - rect.left, rect.bottom - rect.top};
        }

        static Rect_f ToEdges(const Bounds_f& bounds) {
            return {bounds.x, bounds.y, bounds.x + bounds.width, bounds.y + bounds.height};
        }
        template<typename T>
        static constexpr bool Contains(const Bounds<T>& bounds, T x, T y) {
            return bounds.width >= T{} && bounds.height >= T{}
                && x >= bounds.x && x <= bounds.x + bounds.width
                && y >= bounds.y && y <= bounds.y + bounds.height;
        }

        template<typename T>
        static constexpr Bounds<T> Translate(Bounds<T> bounds, T x, T y = T{}) {
            bounds.x += x;
            bounds.y += y;
            return bounds;
        }

        template<typename T>
        static constexpr Bounds<T> Intersect(const Bounds<T>& first, const Bounds<T>& second) {
            const T x = std::max(first.x, second.x);
            const T y = std::max(first.y, second.y);
            return {x, y,
                std::max(T{}, std::min(first.x + first.width, second.x + second.width) - x),
                std::max(T{}, std::min(first.y + first.height, second.y + second.height) - y)};
        }

        template<typename T>
        static constexpr Bounds<T> Inset(const Bounds<T>& bounds, const Insets<T>& insets) {
            return {bounds.x + insets.left, bounds.y + insets.top,
                std::max(T{}, bounds.width - insets.Horizontal()),
                std::max(T{}, bounds.height - insets.Vertical())};
        }

        static float FitScale(Size_f sourceSize, Size_f targetSize) {
            if (!std::isfinite(sourceSize.width) || !std::isfinite(sourceSize.height)
                || !std::isfinite(targetSize.width) || !std::isfinite(targetSize.height)
                || sourceSize.width <= 0 || sourceSize.height <= 0
                || targetSize.width < 0 || targetSize.height < 0) {
                throw std::invalid_argument("FitScale requires positive source and nonnegative finite target sizes");
            }
            return std::min(targetSize.width / sourceSize.width, targetSize.height / sourceSize.height);
        }

        static Bounds<int> RoundOut(const Bounds_f& bounds) {
            if (bounds.width <= 0 || bounds.height <= 0) { return {}; }
            const double left = std::floor(static_cast<double>(bounds.x));
            const double top = std::floor(static_cast<double>(bounds.y));
            const double right = std::ceil(static_cast<double>(bounds.x) + bounds.width);
            const double bottom = std::ceil(static_cast<double>(bounds.y) + bounds.height);
            const auto valid = [](double value) {
                return std::isfinite(value) && value >= std::numeric_limits<int>::min()
                    && value <= std::numeric_limits<int>::max();
            };
            if (!valid(left) || !valid(top) || !valid(right) || !valid(bottom)
                || !valid(right - left) || !valid(bottom - top)) {
                throw std::out_of_range("Pixel bounds exceed the integer coordinate range");
            }
            return {static_cast<int>(left), static_cast<int>(top),
                static_cast<int>(right - left), static_cast<int>(bottom - top)};
        }
    };
}