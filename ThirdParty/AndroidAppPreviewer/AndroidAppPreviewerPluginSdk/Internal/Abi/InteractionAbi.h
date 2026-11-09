#pragma once
#include <AndroidAppPreviewerPluginSdk/AndroidAppPreviewerPlugin.h>

namespace universaldevkit::windows::androidapppreviewerpluginsdk::internal::abi {
    using namespace universaldevkit::windows::androidapppreviewerpluginsdk;
    class InteractionAbi final {
    public:
        static int xp_add_storyboard_animation(
            xp_element* element,
            int trigger,
            const char* name,
            const char* const* keys,
            const char* const* values,
            int count
        );
        static int xp_attach_animations(
            xp_element* root,
            xp_animation_controller* animations
        );
        static int xp_set_page_transition(
            xp_element* root,
            xp_animation_controller* animations,
            const char* from,
            const char* to,
            int backward,
            int visible
        );
        static int xp_add_storyboard_track(
            xp_element* element,
            int trigger,
            int property,
            float from,
            float to,
            int durationMilliseconds,
            int easing
        );
        static int xp_add_visual_state_track(
            xp_element* scope,
            const char* groupName,
            const char* stateName,
            const char* targetName,
            int property,
            float from,
            float to,
            int durationMilliseconds,
            int easing
        );
        static int xp_go_to_visual_state(
            xp_element* scope,
            const char* groupName,
            const char* stateName,
            int useTransitions
        );
        static int xp_scroll_begin(
            xp_element* root,
            xp_animation_controller* animations,
            float x,
            float y
        );
        static int xp_scroll_drag(
            xp_animation_controller* animations,
            float verticalDelta
        );
        static void xp_scroll_end(xp_animation_controller* animations);
        static int xp_set_render_offset_x(
            xp_element* element,
            float value
        );
        static int xp_animate_render_offset_x(
            xp_element* element,
            xp_animation_controller* animations,
            float value,
            int duration_milliseconds
        );
        static int xp_handle_tap(
            xp_element* element,
            xp_animation_controller* animations
        );
        static int xp_handle_pointer_down(
            xp_element* element,
            xp_animation_controller* animations
        );
        static int xp_handle_pointer_up(
            xp_element* element,
            xp_animation_controller* animations
        );
        static xp_animation_controller* xp_create_animation_controller(void);
        static void xp_destroy_animation_controller(xp_animation_controller* animations);
        static xp_interaction_controller* xp_create_interaction_controller(void);
        static void xp_destroy_interaction_controller(xp_interaction_controller* controller);
        static int xp_interaction_pointer_down(
            xp_interaction_controller* controller,
            xp_element* root,
            xp_animation_controller* animations,
            float x,
            float y
        );
        static int xp_interaction_pointer_move(
            xp_interaction_controller* controller,
            float x,
            float y
        );
        static int xp_interaction_pointer_up(
            xp_interaction_controller* controller,
            xp_element* root,
            xp_animation_controller* animations,
            float x,
            float y,
            xp_interaction_result* result
        );
        static int xp_interaction_scroll_wheel(
            xp_interaction_controller* controller,
            xp_element* root,
            float x,
            float y,
            float horizontal_delta,
            float vertical_delta
        );
        static int xp_interaction_update(xp_interaction_controller* controller);
        static int xp_set_animation_playback_rate(
            xp_animation_controller* animations,
            float playbackRate
        );
        static int xp_update_animations(xp_animation_controller* animations);
    };
}