#pragma once
#include <AndroidAppPreviewerPluginSdk/AndroidAppPreviewerPlugin.h>

namespace universaldevkit::windows::androidapppreviewerpluginsdk::internal::abi {
    using namespace universaldevkit::windows::androidapppreviewerpluginsdk;

    class ElementAbi final {
    public:
        static xp_element* xp_create_element(const char* type);
        static void xp_destroy_element(xp_element* element);
        static int xp_items_remove_item(xp_element* target);
        static int xp_add_child(
            xp_element* parent,
            xp_element* child
        );
        static int xp_set_attribute(
            xp_element* element,
            const char* name,
            const char* value
        );
        static xp_element* xp_find_element(
            xp_element* root,
            const char* id
        );
        static int xp_find_element_count(
            xp_element* root,
            const char* id
        );
        static xp_element* xp_find_element_at(
            xp_element* root,
            const char* id,
            int index
        );
        static int xp_layout(
            xp_element* root,
            float width,
            float height
        );
        static xp_element* xp_hit_test(
            xp_element* root,
            float x,
            float y
        );
        static xp_element* xp_hit_test_visual(
            xp_element* root,
            float x,
            float y
        );
        static int xp_hit_test_cursor_kind(
            xp_element* root,
            float x,
            float y
        );
        static int xp_element_bounds(
            const xp_element* element,
            xp_rect* bounds
        );
        static const char* xp_element_id(const xp_element* element);
        static int xp_get_scroll_offsets(
            xp_element* root,
            const char* scroll_viewer_id,
            float* horizontal_offset,
            float* vertical_offset
        );
        static int xp_set_scroll_offsets(
            xp_element* root,
            const char* scroll_viewer_id,
            float horizontal_offset,
            float vertical_offset
        );
        static int xp_scroll_by(
            xp_element* root,
            float x,
            float y,
            float horizontalDelta,
            float verticalDelta
        );
    };
}