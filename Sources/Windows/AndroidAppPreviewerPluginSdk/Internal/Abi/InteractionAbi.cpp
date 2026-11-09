#include "Internal/Abi/InteractionAbi.h"

#include <UniversalDevKit/XamlRuntime/Animation.h>
#include <UniversalDevKit/XamlRuntime/Input.h>

#include "Internal/Bridge/PreviewPluginSdkTypes.h"
#include "Internal/Bridge/ElementTree.h"
#include "Internal/Bridge/Diagnostic.h"

#include <algorithm>
#include <stdexcept>
#include <iterator>
#include <utility>
#include <chrono>
#include <cmath>

namespace universaldevkit::windows::androidapppreviewerpluginsdk::internal::abi {
    using namespace universaldevkit::windows::androidapppreviewerpluginsdk;

    //
    // Методы
    //
    int InteractionAbi::xp_add_storyboard_animation(
        xp_element* element,
        int trigger,
        const char* name,
        const char* const* keys,
        const char* const* values,
        int count
    ) {
        try {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError().clear();
            if (element == nullptr || trigger < 0 || trigger > 6 || count < 0
                || (count > 0 && (keys == nullptr || values == nullptr))) {
                throw std::invalid_argument("invalid storyboard animation");
            }
            xaml::Storyboard storyboard;
            storyboard.trigger = static_cast<xaml::AnimationTrigger>(trigger);
            if (name != nullptr) {
                if (*name == '\0') {
                    throw std::invalid_argument("animation name is required");
                }
                xaml::AnimationTrack track;
                track.name = name;
                for (int index = 0; index < count; ++index) {
                    if (keys[index] == nullptr || values[index] == nullptr) {
                        throw std::invalid_argument("animation settings are required");
                    }
                    track.settings.Set(keys[index], values[index]);
                }
                storyboard.tracks.push_back(std::move(track));
            }
            reinterpret_cast<xaml::Element*>(element)->AddStoryboard(std::move(storyboard));
            return 1;
        } catch (const std::exception& error) {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError() = error.what();
            return 0;
        }
    }

    int InteractionAbi::xp_attach_animations(
        xp_element* root,
        xp_animation_controller* animations
    ) {
        try {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError().clear();
            if (root == nullptr) {
                throw std::invalid_argument("root is required");
            }
            if (animations == nullptr) {
                throw std::invalid_argument("animations is required");
            }
            animations->value.Attach(*reinterpret_cast<xaml::Element*>(root), xaml::AnimationRegistry{}, false);
            return 1;
        } catch (const std::exception& error) {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError() = error.what();
            return 0;
        }
    }

    int InteractionAbi::xp_set_page_transition(
        xp_element* root,
        xp_animation_controller* animations,
        const char* from,
        const char* to,
        int backward,
        int visible
    ) {
        bridge::LastError() = "The template does not define page transitions";
        return 0;
    }

    int InteractionAbi::xp_add_storyboard_track(
        xp_element* element,
        int trigger,
        int property,
        float from,
        float to,
        int durationMilliseconds,
        int easing
    ) {
        try {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError().clear();
            if (element == nullptr || trigger < 0 || trigger > 6 || property < 0 || property > 5
                || durationMilliseconds < 0 || easing < 0 || easing > 1) {
                throw std::invalid_argument("invalid storyboard track");
            }
            xaml::Storyboard storyboard;
            storyboard.trigger = static_cast<xaml::AnimationTrigger>(trigger);
            storyboard.tracks.push_back({
                static_cast<xaml::AnimatedProperty>(property),
                from,
                to,
                std::isnan(from),
                std::isnan(to),
                std::chrono::milliseconds(durationMilliseconds),
                static_cast<xaml::Easing>(easing),
            });
            reinterpret_cast<xaml::Element*>(element)->AddStoryboard(std::move(storyboard));
            return 1;
        } catch (const std::exception& error) {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError() = error.what();
            return 0;
        }
    }

    int InteractionAbi::xp_add_visual_state_track(
        xp_element* scope,
        const char* groupName,
        const char* stateName,
        const char* targetName,
        int property,
        float from,
        float to,
        int durationMilliseconds,
        int easing
    ) {
        try {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError().clear();
            if (scope == nullptr || groupName == nullptr || stateName == nullptr || targetName == nullptr
                || *groupName == '\0' || *stateName == '\0' || *targetName == '\0'
                || property < 0 || property > 5 || durationMilliseconds < 0 || easing < 0 || easing > 1) {
                throw std::invalid_argument("invalid visual state track");
            }
            auto& groups = reinterpret_cast<xaml::Element*>(scope)->VisualStateGroups();
            auto group = std::find_if(groups.begin(), groups.end(), [groupName](const xaml::VisualStateGroup& value) {
                return value.name == groupName;
            });
            if (group == groups.end()) {
                groups.push_back({groupName});
                group = std::prev(groups.end());
            }
            auto state = std::find_if(group->states.begin(), group->states.end(), [stateName](const xaml::VisualState& value) {
                return value.name == stateName;
            });
            if (state == group->states.end()) {
                group->states.push_back({stateName});
                state = std::prev(group->states.end());
            }
            state->tracks.push_back({targetName, {
                static_cast<xaml::AnimatedProperty>(property), from, to, std::isnan(from), std::isnan(to),
                std::chrono::milliseconds(durationMilliseconds), static_cast<xaml::Easing>(easing)}});
            return 1;
        } catch (const std::exception& error) {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError() = error.what();
            return 0;
        }
    }

    int InteractionAbi::xp_go_to_visual_state(
        xp_element* scope,
        const char* groupName,
        const char* stateName,
        int useTransitions
    ) {
        try {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError().clear();
            if (scope == nullptr || groupName == nullptr || stateName == nullptr) {
                throw std::invalid_argument("scope, groupName and stateName are required");
            }
            return xaml::VisualStateManager::GoToState(*reinterpret_cast<xaml::Element*>(scope),
                groupName, stateName, useTransitions != 0) ? 1 : 0;
        } catch (const std::exception& error) {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError() = error.what();
            return 0;
        }
    }

    int InteractionAbi::xp_scroll_begin(
        xp_element* root,
        xp_animation_controller* animations,
        float x,
        float y
    ) {
        try {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError().clear();
            if (root == nullptr || animations == nullptr || !std::isfinite(x) || !std::isfinite(y)) {
                throw std::invalid_argument("root, animations and finite coordinates are required");
            }
            xaml::Element* const scrollViewer = universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::ElementTree::FindScrollViewer(
                *reinterpret_cast<xaml::Element*>(root), x, y);
            if (scrollViewer == nullptr) {
                return 0;
            }
            animations->scrollController.Begin(*scrollViewer);
            return 1;
        } catch (const std::exception& error) {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError() = error.what();
            return 0;
        }
    }

    int InteractionAbi::xp_scroll_drag(
        xp_animation_controller* animations,
        float verticalDelta
    ) {
        try {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError().clear();
            if (animations == nullptr || !std::isfinite(verticalDelta)) {
                throw std::invalid_argument("animations and finite vertical delta are required");
            }
            return animations->scrollController.Drag(verticalDelta) ? 1 : 0;
        } catch (const std::exception& error) {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError() = error.what();
            return 0;
        }
    }

    void InteractionAbi::xp_scroll_end(xp_animation_controller* animations) {
        if (animations != nullptr) {
            animations->scrollController.End();
        }
    }

    int InteractionAbi::xp_set_render_offset_x(
        xp_element* element,
        float value
    ) {
        try {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError().clear();
            if (element == nullptr || !std::isfinite(value)) {
                throw std::invalid_argument("element and finite value are required");
            }
            reinterpret_cast<xaml::Element*>(element)->SetRenderOffsetX(value);
            return 1;
        } catch (const std::exception& error) {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError() = error.what();
            return 0;
        }
    }

    int InteractionAbi::xp_animate_render_offset_x(
        xp_element* element,
        xp_animation_controller* animations,
        float value,
        int durationMilliseconds
    ) {
        try {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError().clear();
            if (element == nullptr || animations == nullptr || !std::isfinite(value)
                || durationMilliseconds < 0) {
                throw std::invalid_argument("element, animations, value and duration are required");
            }
            xaml::Element& target = *reinterpret_cast<xaml::Element*>(element);
            animations->value.Animate(
                target,
                xaml::AnimatedProperty::renderOffsetX,
                target.RenderOffsetX(),
                value,
                std::chrono::milliseconds(durationMilliseconds));
            return 1;
        } catch (const std::exception& error) {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError() = error.what();
            return 0;
        }
    }

    int InteractionAbi::xp_handle_tap(
        xp_element* element,
        xp_animation_controller* animations
    ) {
        try {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError().clear();
            if (element == nullptr || animations == nullptr) {
                throw std::invalid_argument("element and animations are required");
            }
            xaml::Element& target = *reinterpret_cast<xaml::Element*>(element);
            if (!xaml::HandleTap(target)) {
                return 0;
            }
            if (target.Type() == xaml::ElementType::toggleSwitch) {
                animations->value.Start(target, xaml::AnimationTrigger::toggled);
            }
            return 1;
        } catch (const std::exception& error) {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError() = error.what();
            return 0;
        }
    }

    int InteractionAbi::xp_handle_pointer_down(
        xp_element* element,
        xp_animation_controller* animations
    ) {
        try {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError().clear();
            if (element == nullptr || animations == nullptr) {
                throw std::invalid_argument("element and animations are required");
            }
            xaml::Element& target = *reinterpret_cast<xaml::Element*>(element);
            animations->value.Start(target, xaml::AnimationTrigger::pointerDown);
            return 1;
        } catch (const std::exception& error) {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError() = error.what();
            return 0;
        }
    }

    int InteractionAbi::xp_handle_pointer_up(
        xp_element* element,
        xp_animation_controller* animations
    ) {
        try {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError().clear();
            if (element == nullptr || animations == nullptr) {
                throw std::invalid_argument("element and animations are required");
            }
            xaml::Element& target = *reinterpret_cast<xaml::Element*>(element);
            if (target.Type() == xaml::ElementType::button) {
                animations->value.Start(target, xaml::AnimationTrigger::pointerUp);
                return 1;
            }
            return InteractionAbi::xp_handle_tap(element, animations);
        } catch (const std::exception& error) {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError() = error.what();
            return 0;
        }
    }

    xp_animation_controller* InteractionAbi::xp_create_animation_controller(void) {
        try {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError().clear();
            return new xp_animation_controller();
        } catch (const std::exception& error) {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError() = error.what();
            return nullptr;
        }
    }

    void InteractionAbi::xp_destroy_animation_controller(xp_animation_controller* animations) {
        delete animations;
    }

    xp_interaction_controller* InteractionAbi::xp_create_interaction_controller(void) {
        return new xp_interaction_controller();
    }

    void InteractionAbi::xp_destroy_interaction_controller(xp_interaction_controller* controller) {
        delete controller;
    }

    int InteractionAbi::xp_interaction_pointer_down(
        xp_interaction_controller* controller,
        xp_element* root,
        xp_animation_controller* animations,
        float x,
        float y
    ) {
        if (controller == nullptr || root == nullptr || animations == nullptr) {
            return 0;
        }
        controller->value.PointerDown(
            *reinterpret_cast<xaml::Element*>(root),
            animations->value,
            x,
            y);
        return controller->value.HasCapture() ? 1 : 0;
    }

    int InteractionAbi::xp_interaction_pointer_move(
        xp_interaction_controller* controller,
        float x,
        float y
    ) {
        return controller != nullptr && controller->value.PointerMove(x, y) ? 1 : 0;
    }

    int InteractionAbi::xp_interaction_pointer_up(
        xp_interaction_controller* controller,
        xp_element* root,
        xp_animation_controller* animations,
        float x,
        float y,
        xp_interaction_result* result
    ) {
        if (controller == nullptr || root == nullptr || animations == nullptr || result == nullptr) {
            return 0;
        }
        const xaml::GestureResult nativeResult = controller->value.PointerUp(
            *reinterpret_cast<xaml::Element*>(root), animations->value, x, y);
        result->kind = static_cast<int>(nativeResult.kind);
        result->direction = static_cast<int>(nativeResult.direction);
        result->target = reinterpret_cast<xp_element*>(nativeResult.target);
        result->item_index = nativeResult.itemIndex;
        return 1;
    }

    int InteractionAbi::xp_interaction_scroll_wheel(
        xp_interaction_controller* controller,
        xp_element* root,
        float x,
        float y,
        float horizontalDelta,
        float verticalDelta
    ) {
        return controller != nullptr && root != nullptr
            && controller->value.ScrollWheel(*reinterpret_cast<xaml::Element*>(root), x, y, horizontalDelta, verticalDelta) ? 1 : 0;
    }

    int InteractionAbi::xp_interaction_update(xp_interaction_controller* controller) {
        return controller != nullptr && controller->value.Update() ? 1 : 0;
    }

    int InteractionAbi::xp_set_animation_playback_rate(
        xp_animation_controller* animations,
        float playbackRate
    ) {
        try {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError().clear();
            if (animations == nullptr || !std::isfinite(playbackRate)) {
                throw std::invalid_argument("animations and finite playbackRate are required");
            }
            animations->value.SetPlaybackRate(playbackRate);
            return 1;
        } catch (const std::exception& error) {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError() = error.what();
            return 0;
        }
    }

    int InteractionAbi::xp_update_animations(xp_animation_controller* animations) {
        try {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError().clear();
            if (animations == nullptr) {
                throw std::invalid_argument("animations are required");
            }
            const bool wasScrolling = animations->scrollController.Update();
            const bool wasAnimating = animations->value.IsAnimating();
            animations->value.Update();
            return wasAnimating || animations->value.IsAnimating() || wasScrolling ? 1 : 0;
        } catch (const std::exception& error) {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError() = error.what();
            return -1;
        }
    }
} // namespace universaldevkit::windows::androidapppreviewerpluginsdk::internal::abi