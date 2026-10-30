#pragma once
#include <UniversalDevKit/Helpers/Math/Motion.h>
#include <UniversalDevKit/Helpers/Math/Color.h>

#include "Config.h"
#include "Export.h"

#include <unordered_map>
#include <chrono>
#include <string>
#include <vector>
#include <array>

namespace universaldevkit::xamlruntime {

    enum class AnimatedProperty {
        opacity,
        renderOffsetX,
        renderOffsetY,
        height,
        toggleProgress,
        pressProgress,
        background,
        foreground,
        borderColor,
        tint,
    };

    enum class AnimationTrigger {
        pointerDown,
        pointerUp,
        toggled,
        show,
        hide,
        parentShow,
        parentHide,
        visualState,
    };

    namespace attr { using Color = universaldevkit::helpers::math::Color; }
    using Easing = universaldevkit::helpers::math::Easing;

    class UNIVERSALDEVKIT_XAMLRUNTIME_API AnimationSettings final {
    public:
        void Set(std::string name, std::string value);
        const std::string& Get(const std::string& name) const;
        float Number(const std::string& name, float fallback) const;
        const std::unordered_map<std::string, std::string>& Values() const;

    private:
        std::unordered_map<std::string, std::string> values;
    };

    struct UNIVERSALDEVKIT_XAMLRUNTIME_API AnimationTrack {
        AnimatedProperty property = AnimatedProperty::opacity;
        float from = 0.0f;
        float to = 0.0f;
        bool fromCurrent = false;
        bool toToggleState = false;
        std::chrono::milliseconds duration{};
        Easing easing = Easing::linear;
        std::string name;
        AnimationSettings settings;
        bool isColor = false;
        std::array<float, 4> fromColor{};
        std::array<float, 4> toColor{};

        static AnimationTrack Color(AnimatedProperty property, const attr::Color& from, const attr::Color& to,
            std::chrono::milliseconds duration, Easing easing = Easing::linear, bool fromCurrent = false);
    };

    struct Storyboard {
        AnimationTrigger trigger = AnimationTrigger::pointerDown;
        std::vector<AnimationTrack> tracks;
    };

    struct VisualStateTrack {
        std::string targetName;
        AnimationTrack animation;
    };

    struct VisualStateSetter {
        std::string targetName;
        std::string property;
        std::string value;
    };

    struct VisualState {
        std::string name;
        std::vector<VisualStateTrack> tracks;
        std::vector<VisualStateSetter> setters;
    };

    struct VisualStateGroup {
        std::string name;
        std::string currentState;
        std::vector<VisualState> states;
    };
}