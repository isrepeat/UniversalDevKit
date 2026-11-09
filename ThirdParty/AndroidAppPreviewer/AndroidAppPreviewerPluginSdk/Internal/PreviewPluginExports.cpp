#include <AndroidAppPreviewerPluginSdk/AndroidAppPreviewerPlugin.h>

#include "Internal/Abi/XamlCompletionAbi.h"
#include "Internal/Abi/InteractionAbi.h"
#include "Internal/Abi/DiagnosticAbi.h"
#include "Internal/Abi/RenderingAbi.h"
#include "Internal/Abi/MetadataAbi.h"
#include "Internal/Abi/ElementAbi.h"
#include "Internal/Abi/SessionAbi.h"

namespace details {
    using namespace universaldevkit::windows::androidapppreviewerpluginsdk;
    using namespace universaldevkit::windows::androidapppreviewerpluginsdk::internal::abi;

    const xp_metadata_abi metadataAbi{
        android_app_previewer_plugin_abi_table_version,
        sizeof(xp_metadata_abi),
        &MetadataAbi::xp_get_abi_version,
        &MetadataAbi::xp_last_error,
        &MetadataAbi::xp_get_plugin_info,
        &MetadataAbi::xp_get_initial_page_id,
        &MetadataAbi::xp_get_navigation_graph,
        &MetadataAbi::xp_navigate
    };

    const xp_session_abi sessionAbi{
        android_app_previewer_plugin_abi_table_version,
        sizeof(xp_session_abi),
        &SessionAbi::xp_create_session,
        &SessionAbi::xp_destroy_session,
        &SessionAbi::xp_session_load_page,
        &SessionAbi::xp_session_current_page,
        &SessionAbi::xp_session_is_transitioning,
        &SessionAbi::xp_session_navigate_preview_route,
        &SessionAbi::xp_session_navigate_preview_route_path,
        &SessionAbi::xp_session_preview_route_graph,
        &SessionAbi::xp_session_preview_page_title,
        &SessionAbi::xp_session_apply_preview_scenario,
        &SessionAbi::xp_session_export_preview_state,
        &SessionAbi::xp_session_can_save_preview_state,
        &SessionAbi::xp_session_reload_markup,
        &SessionAbi::xp_session_resize,
        &SessionAbi::xp_session_set_animation_playback_rate,
        &SessionAbi::xp_session_set_status,
        &SessionAbi::xp_session_pointer_down,
        &SessionAbi::xp_session_pointer_move,
        &SessionAbi::xp_session_pointer_up,
        &SessionAbi::xp_session_pointer_cancel,
        &SessionAbi::xp_session_cursor_kind,
        &SessionAbi::xp_session_inspect,
        &SessionAbi::xp_session_set_inspection_wireframe,
        &SessionAbi::xp_session_set_selected_wireframe,
        &SessionAbi::xp_session_clear_inspection_wireframe,
        &SessionAbi::xp_session_clear_selected_inspection_element,
        &SessionAbi::xp_session_select_inspection_element,
        &SessionAbi::xp_session_pin_inspection_element,
        &SessionAbi::xp_session_update,
        &SessionAbi::xp_session_render_angle_surface
    };

    const xp_element_abi elementAbi{
        android_app_previewer_plugin_abi_table_version,
        sizeof(xp_element_abi),
        &ElementAbi::xp_create_element,
        &ElementAbi::xp_destroy_element,
        &ElementAbi::xp_items_remove_item,
        &ElementAbi::xp_add_child,
        &ElementAbi::xp_set_attribute,
        &ElementAbi::xp_find_element,
        &ElementAbi::xp_find_element_count,
        &ElementAbi::xp_find_element_at,
        &ElementAbi::xp_layout,
        &ElementAbi::xp_hit_test,
        &ElementAbi::xp_hit_test_visual,
        &ElementAbi::xp_hit_test_cursor_kind,
        &ElementAbi::xp_element_bounds,
        &ElementAbi::xp_element_id,
        &ElementAbi::xp_get_scroll_offsets,
        &ElementAbi::xp_set_scroll_offsets,
        &ElementAbi::xp_scroll_by
    };

    const xp_interaction_abi interactionAbi{
        android_app_previewer_plugin_abi_table_version,
        sizeof(xp_interaction_abi),
        &InteractionAbi::xp_add_storyboard_animation,
        &InteractionAbi::xp_attach_animations,
        &InteractionAbi::xp_set_page_transition,
        &InteractionAbi::xp_add_storyboard_track,
        &InteractionAbi::xp_add_visual_state_track,
        &InteractionAbi::xp_go_to_visual_state,
        &InteractionAbi::xp_scroll_begin,
        &InteractionAbi::xp_scroll_drag,
        &InteractionAbi::xp_scroll_end,
        &InteractionAbi::xp_set_render_offset_x,
        &InteractionAbi::xp_animate_render_offset_x,
        &InteractionAbi::xp_handle_tap,
        &InteractionAbi::xp_handle_pointer_down,
        &InteractionAbi::xp_handle_pointer_up,
        &InteractionAbi::xp_create_animation_controller,
        &InteractionAbi::xp_destroy_animation_controller,
        &InteractionAbi::xp_create_interaction_controller,
        &InteractionAbi::xp_destroy_interaction_controller,
        &InteractionAbi::xp_interaction_pointer_down,
        &InteractionAbi::xp_interaction_pointer_move,
        &InteractionAbi::xp_interaction_pointer_up,
        &InteractionAbi::xp_interaction_scroll_wheel,
        &InteractionAbi::xp_interaction_update,
        &InteractionAbi::xp_set_animation_playback_rate,
        &InteractionAbi::xp_update_animations
    };

    const xp_rendering_abi renderingAbi{
        android_app_previewer_plugin_abi_table_version,
        sizeof(xp_rendering_abi),
        &RenderingAbi::xp_create_angle_surface,
        &RenderingAbi::xp_destroy_angle_surface,
        &RenderingAbi::xp_render_angle_surface,
        &RenderingAbi::xp_render,
        &RenderingAbi::xp_render_angle
    };

    const xp_xaml_completion_abi xamlCompletionAbi{
        android_app_previewer_plugin_abi_table_version,
        sizeof(xp_xaml_completion_abi),
        &XamlCompletionAbi::xp_supported_attribute_count,
        &XamlCompletionAbi::xp_supported_attribute_name,
        &XamlCompletionAbi::xp_supported_element_count,
        &XamlCompletionAbi::xp_supported_element_name
    };

    const xp_logging_abi loggingAbi{
        android_app_previewer_plugin_abi_table_version,
        sizeof(xp_logging_abi),
        &DiagnosticAbi::xp_configure_logging,
        &DiagnosticAbi::xp_log_info
    };

    const xp_plugin_abi pluginAbi{
        android_app_previewer_plugin_abi_table_version,
        sizeof(xp_plugin_abi),
        metadataAbi,
        sessionAbi,
        elementAbi,
        interactionAbi,
        renderingAbi,
        xamlCompletionAbi,
        loggingAbi
    };
} // namespace details

namespace universaldevkit::windows::androidapppreviewerpluginsdk {
    extern "C" ANDROID_APP_PREVIEWER_PLUGIN_ABI const xp_plugin_abi* XP_PLUGIN_CALL xp_get_abi(uint32_t requestedVersion) {
        return requestedVersion == android_app_previewer_plugin_abi_table_version ? &details::pluginAbi : nullptr;
    }
} // namespace universaldevkit::windows::androidapppreviewerpluginsdk