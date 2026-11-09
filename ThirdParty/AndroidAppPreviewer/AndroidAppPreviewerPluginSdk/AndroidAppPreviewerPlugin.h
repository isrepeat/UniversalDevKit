#pragma once
#include "Export.h"
#include <stdint.h>

#if defined(UNIVERSALDEVKIT_ANDROIDAPPPREVIEWERPLUGINSDK_DYNAMIC)
#define ANDROID_APP_PREVIEWER_PLUGIN_ABI UNIVERSALDEVKIT_ANDROIDAPPPREVIEWERPLUGINSDK_API
#elif defined(_WIN32)
#define ANDROID_APP_PREVIEWER_PLUGIN_ABI __declspec(dllexport)
#else
#define ANDROID_APP_PREVIEWER_PLUGIN_ABI
#endif

#if defined(_MSC_VER)
#define XP_PLUGIN_CALL __cdecl
#else
#define XP_PLUGIN_CALL
#endif

#ifdef __cplusplus
namespace universaldevkit::windows::androidapppreviewerpluginsdk {
    extern "C" {
#endif
        enum {
            android_app_previewer_plugin_abi_version = 1,
            android_app_previewer_plugin_abi_table_version = 1
        };

        typedef struct xp_element xp_element;
        typedef struct xp_session xp_session;
        typedef struct xp_angle_surface xp_angle_surface;
        typedef struct xp_animation_controller xp_animation_controller;
        typedef struct xp_interaction_controller xp_interaction_controller;

        typedef struct xp_rect {
            float x;
            float y;
            float width;
            float height;
        } xp_rect;

        typedef struct xp_color {
            float red;
            float green;
            float blue;
            float alpha;
        } xp_color;

        typedef struct xp_session_inspection_result {
            int line;
            int column;
            char sourcePath[1024];
            xp_rect bounds;
        } xp_session_inspection_result;

        typedef struct xp_interaction_result {
            int kind;
            int direction;
            xp_element* target;
            int item_index;
        } xp_interaction_result;

        typedef enum xp_command_type {
            xp_command_type_begin_clip,
            xp_command_type_end_clip,
            xp_command_type_outline,
            xp_command_type_rounded_rect,
            xp_command_type_rounded_rect_outline,
            xp_command_type_text,
            xp_command_type_image
        } xp_command_type;

        typedef struct xp_command {
            int type;
            xp_rect bounds;
            xp_color color;
            float value;
            char text[512];
            char auxiliary[128];
        } xp_command;

        // Все строки ABI имеют UTF-8. Поля добавляются только в конец таблицы.
        typedef struct xp_metadata_abi {
            uint32_t version;
            uint32_t size;
            uint32_t(XP_PLUGIN_CALL* get_abi_version)(void);
            const char* (XP_PLUGIN_CALL* last_error)(void);
            int(XP_PLUGIN_CALL* get_plugin_info)(char*, int);
            int(XP_PLUGIN_CALL* get_initial_page_id)(void*, char*, int);
            int(XP_PLUGIN_CALL* get_navigation_graph)(void*, char*, int);
            int(XP_PLUGIN_CALL* navigate)(void*, const char*);
        } xp_metadata_abi;

        typedef struct xp_session_abi {
            uint32_t version;
            uint32_t size;
            xp_session* (XP_PLUGIN_CALL* create)(int, int);
            void(XP_PLUGIN_CALL* destroy)(xp_session*);
            int(XP_PLUGIN_CALL* load_page)(xp_session*, const char*);
            int(XP_PLUGIN_CALL* current_page)(xp_session*, char*, int);
            int(XP_PLUGIN_CALL* is_transitioning)(xp_session*);
            int(XP_PLUGIN_CALL* navigate_preview_route)(xp_session*, const char*);
            int(XP_PLUGIN_CALL* navigate_preview_route_path)(xp_session*, const char*);
            int(XP_PLUGIN_CALL* preview_route_graph)(xp_session*, char*, int);
            int(XP_PLUGIN_CALL* preview_page_title)(xp_session*, const char*, char*, int);
            int(XP_PLUGIN_CALL* apply_preview_scenario)(xp_session*, const char*, const char*);
            int(XP_PLUGIN_CALL* export_preview_state)(xp_session*);
            int(XP_PLUGIN_CALL* can_save_preview_state)(xp_session*);
            int(XP_PLUGIN_CALL* reload_markup)(xp_session*, const char*, const char*, const char*);
            int(XP_PLUGIN_CALL* resize)(xp_session*, int, int);
            int(XP_PLUGIN_CALL* set_animation_playback_rate)(xp_session*, float);
            int(XP_PLUGIN_CALL* set_status)(xp_session*, const char*);
            int(XP_PLUGIN_CALL* pointer_down)(xp_session*, float, float);
            int(XP_PLUGIN_CALL* pointer_move)(xp_session*, float, float);
            int(XP_PLUGIN_CALL* pointer_up)(xp_session*, float, float);
            int(XP_PLUGIN_CALL* pointer_cancel)(xp_session*);
            int(XP_PLUGIN_CALL* cursor_kind)(xp_session*, float, float);
            int(XP_PLUGIN_CALL* inspect)(xp_session*, float, float, xp_session_inspection_result*);
            int(XP_PLUGIN_CALL* set_inspection_wireframe)(xp_session*, float, int, xp_color, xp_color, xp_color);
            int(XP_PLUGIN_CALL* set_selected_wireframe)(xp_session*, float, int, xp_color, xp_color, xp_color);
            int(XP_PLUGIN_CALL* clear_inspection_wireframe)(xp_session*);
            int(XP_PLUGIN_CALL* clear_selected_inspection_element)(xp_session*);
            int(XP_PLUGIN_CALL* select_inspection_element)(xp_session*, const char*, int, int);
            int(XP_PLUGIN_CALL* pin_inspection_element)(xp_session*);
            int(XP_PLUGIN_CALL* update)(xp_session*);
            int(XP_PLUGIN_CALL* render_angle_surface)(xp_session*, xp_angle_surface*, unsigned char*, int, int);
        } xp_session_abi;

        typedef struct xp_element_abi {
            uint32_t version;
            uint32_t size;
            xp_element* (XP_PLUGIN_CALL* create)(const char*);
            void(XP_PLUGIN_CALL* destroy)(xp_element*);
            int(XP_PLUGIN_CALL* items_remove_item)(xp_element*);
            int(XP_PLUGIN_CALL* add_child)(xp_element*, xp_element*);
            int(XP_PLUGIN_CALL* set_attribute)(xp_element*, const char*, const char*);
            xp_element* (XP_PLUGIN_CALL* find)(xp_element*, const char*);
            int(XP_PLUGIN_CALL* find_count)(xp_element*, const char*);
            xp_element* (XP_PLUGIN_CALL* find_at)(xp_element*, const char*, int);
            int(XP_PLUGIN_CALL* layout)(xp_element*, float, float);
            xp_element* (XP_PLUGIN_CALL* hit_test)(xp_element*, float, float);
            xp_element* (XP_PLUGIN_CALL* hit_test_visual)(xp_element*, float, float);
            int(XP_PLUGIN_CALL* hit_test_cursor_kind)(xp_element*, float, float);
            int(XP_PLUGIN_CALL* bounds)(const xp_element*, xp_rect*);
            const char* (XP_PLUGIN_CALL* id)(const xp_element*);
            int(XP_PLUGIN_CALL* get_scroll_offsets)(xp_element*, const char*, float*, float*);
            int(XP_PLUGIN_CALL* set_scroll_offsets)(xp_element*, const char*, float, float);
            int(XP_PLUGIN_CALL* scroll_by)(xp_element*, float, float, float, float);
        } xp_element_abi;

        typedef struct xp_interaction_abi {
            uint32_t version;
            uint32_t size;
            int(XP_PLUGIN_CALL* add_storyboard_animation)(xp_element*, int, const char*, const char* const*,
                const char* const*, int);
            int(XP_PLUGIN_CALL* attach_animations)(xp_element*, xp_animation_controller*);
            int(XP_PLUGIN_CALL* set_page_transition)(xp_element*, xp_animation_controller*, const char*, const char*, int,
                int);
            int(XP_PLUGIN_CALL* add_storyboard_track)(xp_element*, int, int, float, float, int, int);
            int(XP_PLUGIN_CALL* add_visual_state_track)(xp_element*, const char*, const char*, const char*, int, float,
                float, int, int);
            int(XP_PLUGIN_CALL* go_to_visual_state)(xp_element*, const char*, const char*, int);
            int(XP_PLUGIN_CALL* scroll_begin)(xp_element*, xp_animation_controller*, float, float);
            int(XP_PLUGIN_CALL* scroll_drag)(xp_animation_controller*, float);
            void(XP_PLUGIN_CALL* scroll_end)(xp_animation_controller*);
            int(XP_PLUGIN_CALL* set_render_offset_x)(xp_element*, float);
            int(XP_PLUGIN_CALL* animate_render_offset_x)(xp_element*, xp_animation_controller*, float, int);
            int(XP_PLUGIN_CALL* handle_tap)(xp_element*, xp_animation_controller*);
            int(XP_PLUGIN_CALL* handle_pointer_down)(xp_element*, xp_animation_controller*);
            int(XP_PLUGIN_CALL* handle_pointer_up)(xp_element*, xp_animation_controller*);
            xp_animation_controller* (XP_PLUGIN_CALL* create_animation_controller)(void);
            void(XP_PLUGIN_CALL* destroy_animation_controller)(xp_animation_controller*);
            xp_interaction_controller* (XP_PLUGIN_CALL* create_interaction_controller)(void);
            void(XP_PLUGIN_CALL* destroy_interaction_controller)(xp_interaction_controller*);
            int(XP_PLUGIN_CALL* pointer_down)(xp_interaction_controller*, xp_element*, xp_animation_controller*, float,
                float);
            int(XP_PLUGIN_CALL* pointer_move)(xp_interaction_controller*, float, float);
            int(XP_PLUGIN_CALL* pointer_up)(xp_interaction_controller*, xp_element*, xp_animation_controller*, float, float,
                xp_interaction_result*);
            int(XP_PLUGIN_CALL* scroll_wheel)(xp_interaction_controller*, xp_element*, float, float, float, float);
            int(XP_PLUGIN_CALL* update)(xp_interaction_controller*);
            int(XP_PLUGIN_CALL* set_animation_playback_rate)(xp_animation_controller*, float);
            int(XP_PLUGIN_CALL* update_animations)(xp_animation_controller*);
        } xp_interaction_abi;

        typedef struct xp_rendering_abi {
            uint32_t version;
            uint32_t size;
            xp_angle_surface* (XP_PLUGIN_CALL* create_angle_surface)(int, int, const char*, const char*);
            void(XP_PLUGIN_CALL* destroy_angle_surface)(xp_angle_surface*);
            int(XP_PLUGIN_CALL* render_angle_surface)(xp_angle_surface*, const xp_element*, unsigned char*, int, int);
            int(XP_PLUGIN_CALL* render)(const xp_element*, xp_command*, int);
            int(XP_PLUGIN_CALL* render_angle)(const xp_element*, const char*, int, int, const char*, unsigned char*, int,
                int);
        } xp_rendering_abi;

        typedef struct xp_xaml_completion_abi {
            uint32_t version;
            uint32_t size;
            int(XP_PLUGIN_CALL* xaml_supported_attribute_count)(const char*);
            const char* (XP_PLUGIN_CALL* xaml_supported_attribute_name)(const char*, int);
            int(XP_PLUGIN_CALL* xaml_supported_element_count)(void);
            const char* (XP_PLUGIN_CALL* xaml_supported_element_name)(int);
        } xp_xaml_completion_abi;

        typedef struct xp_logging_abi {
            uint32_t version;
            uint32_t size;
            void(XP_PLUGIN_CALL* configure)(const char*);
            void(XP_PLUGIN_CALL* info)(const char*);
        } xp_logging_abi;

        typedef struct xp_plugin_abi {
            uint32_t version;
            uint32_t size;
            xp_metadata_abi metadata;
            xp_session_abi session;
            xp_element_abi element;
            xp_interaction_abi interaction;
            xp_rendering_abi rendering;
            xp_xaml_completion_abi xaml_completion;
            xp_logging_abi logging;
        } xp_plugin_abi;

        // Единственный экспорт DLL. nullptr означает неподдерживаемую версию ABI.
        ANDROID_APP_PREVIEWER_PLUGIN_ABI const xp_plugin_abi* XP_PLUGIN_CALL xp_get_abi(uint32_t requestedVersion);
#ifdef __cplusplus
    } // extern "C"
} // namespace universaldevkit::windows::androidapppreviewerpluginsdk
#endif