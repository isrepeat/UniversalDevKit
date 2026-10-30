#pragma once
#include <stdexcept>
#include <cmath>

namespace universaldevkit::helpers::math {
    enum class Easing { linear, cubicOut };

    struct MotionStep {
        float distance;
        float velocity;
    };

    class Motion final {
    public:
        static constexpr float Ease(Easing easing, float progress) {
            const float inverse = 1 - progress;
            return easing == Easing::cubicOut ? 1 - inverse * inverse * inverse : progress;
        }

        static MotionStep ExponentialStep(float velocity, float deceleration, float seconds) {
            if (!std::isfinite(velocity) || !std::isfinite(deceleration) || !std::isfinite(seconds)
                || deceleration < 0 || seconds < 0) {
                throw std::invalid_argument("Exponential motion requires finite velocity and nonnegative deceleration/time");
            }
            if (deceleration == 0) { return {velocity * seconds, velocity}; }
            const float exponent = -deceleration * seconds;
            return {velocity * -std::expm1(exponent) / deceleration, velocity * std::exp(exponent)};
        }
    };
}