#pragma once
#include <cmath>

namespace universaldevkit::helpers::math {
    struct Color {
        float red = 1;
        float green = 1;
        float blue = 1;
        float alpha = 1;
        bool operator==(const Color&) const = default;
    };

    class ColorMath final {
    public:
        static Color Interpolate(Color from, Color to, float progress) {
            return {std::lerp(from.red, to.red, progress), std::lerp(from.green, to.green, progress),
                std::lerp(from.blue, to.blue, progress), std::lerp(from.alpha, to.alpha, progress)};
        }

        static constexpr Color WithOpacity(Color color, float opacity) {
            color.alpha *= opacity;
            return color;
        }
    };
}