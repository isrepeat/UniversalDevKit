#pragma once

#include <unordered_map>
#include <string>
#include <chrono>
#include <vector>
#include <array>

namespace xaml {
    namespace attr { struct Color; }

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

    enum class Easing {
        linear,
        cubicOut,
    };

    class AnimationSettings final {
    public:
        void Set(std::string name, std::string value);
        const std::string& Get(const std::string& name) const;
        float Number(const std::string& name, float fallback) const;
        const std::unordered_map<std::string, std::string>& Values() const;

    private:
        std::unordered_map<std::string, std::string> values;
    };

    struct AnimationTrack {
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