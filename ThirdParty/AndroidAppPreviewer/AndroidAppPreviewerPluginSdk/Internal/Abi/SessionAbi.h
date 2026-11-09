#pragma once
#include <UniversalDevKit/XamlRuntime/XamlLayout.h>
#include <AndroidAppPreviewerPluginSdk/AndroidAppPreviewerPlugin.h>

namespace universaldevkit::windows::androidapppreviewerpluginsdk::internal::abi {
    using namespace universaldevkit::windows::androidapppreviewerpluginsdk;

    class SessionAbi final {
    public:
        static xp_session* xp_create_session(
            int width,
            int height
        );
        static void xp_destroy_session(xp_session* session);
        static int xp_session_load_page(
            xp_session* session,
            const char* page
        );
        static int xp_session_current_page(
            xp_session* session,
            char* page,
            int capacity
        );
        static int xp_session_is_transitioning(xp_session* session);
        static int xp_session_navigate_preview_route(
            xp_session* session,
            const char* target
        );
        static int xp_session_navigate_preview_route_path(
            xp_session* session,
            const char* path
        );
        static int xp_session_preview_route_graph(
            xp_session* session,
            char* graph,
            int capacity
        );
        static int xp_session_preview_page_title(
            xp_session* session,
            const char* page,
            char* title,
            int capacity
        );
        static int xp_session_apply_preview_scenario(
            xp_session* session,
            const char* page,
            const char* json
        );
        static int xp_session_export_preview_state(xp_session* session);
        static int xp_session_can_save_preview_state(xp_session* session);
        static int xp_session_reload_markup(
            xp_session* session,
            const char* page,
            const char* markup,
            const char* sourcePath
        );
        static int xp_session_resize(
            xp_session* session,
            int width,
            int height
        );
        static int xp_session_set_animation_playback_rate(
            xp_session* session,
            float value
        );
        static int xp_session_set_status(
            xp_session* session,
            const char* value
        );
        static int xp_session_pointer_down(
            xp_session* session,
            float x,
            float y
        );
        static int xp_session_pointer_move(
            xp_session* session,
            float x,
            float y
        );
        static int xp_session_pointer_up(
            xp_session* session,
            float x,
            float y
        );
        static int xp_session_pointer_cancel(xp_session* session);
        static int xp_session_cursor_kind(
            xp_session* session,
            float x,
            float y
        );
        static int xp_session_inspect(
            xp_session* session,
            float x,
            float y,
            xp_session_inspection_result* result
        );
        static int xp_session_set_inspection_wireframe(
            xp_session* session,
            float thickness,
            int lineStyle,
            xp_color color,
            xp_color marginColor,
            xp_color paddingColor
        );
        static int xp_session_set_selected_wireframe(
            xp_session* session,
            float thickness,
            int lineStyle,
            xp_color color,
            xp_color marginColor,
            xp_color paddingColor
        );
        static int xp_session_clear_inspection_wireframe(xp_session* session);
        static int xp_session_clear_selected_inspection_element(xp_session* session);
        static int xp_session_select_inspection_element(
            xp_session* session,
            const char* sourcePath,
            int line,
            int column
        );
        static int xp_session_pin_inspection_element(xp_session* session);
        static int xp_session_update(xp_session* session);
        static int xp_session_render_angle_surface(
            xp_session* session,
            xp_angle_surface* surface,
            unsigned char* destination,
            int destinationStride,
            int destinationCapacity
        );

    private:
        static bool LoadPage(
            xp_session& session,
            const char* page);
        static bool ApplyScenario(
            xp_session& session,
            const char* page,
            const char* json);
        static bool ReloadMarkup(
            xp_session& session,
            const char* page,
            const char* markup,
            const char* sourcePath);
        static bool Inspect(
            xp_session& session,
            float x,
            float y,
            xp_session_inspection_result& result);
        static bool SetInspectionWireframe(
            xp_session& session,
            float thickness,
            int lineStyle,
            xp_color color,
            xp_color marginColor,
            xp_color paddingColor);
        static bool Update(xp_session& session);
        static bool Render(
            xp_session& session,
            xp_angle_surface& surface,
            unsigned char* destination,
            int destinationStride,
            int destinationCapacity);
        static void ClearInspectionWireframe(xp_session& session);
        static void ClearSelectedWireframe(xp_session& session);
        static void SetInspectionWireframe(
            xp_session& session,
            xaml::Element& element);
        static void SetSelectedWireframe(
            xp_session& session,
            xaml::Element& element);
    };
}