#include "Internal/Abi/ElementAbi.h"

#include <UniversalDevKit/XamlRuntime/ElementBuilder.h>
#include <UniversalDevKit/XamlRuntime/Input.h>

#include "Internal/Bridge/ElementTree.h"
#include "Internal/Bridge/Diagnostic.h"
#include "Internal/Bridge/TextBuffer.h"

#include <algorithm>
#include <stdexcept>
#include <string>
#include <cmath>

namespace universaldevkit::windows::androidapppreviewerpluginsdk::internal::abi {
    using namespace universaldevkit::windows::androidapppreviewerpluginsdk;

    //
    // Методы
    //
    xp_element* ElementAbi::xp_create_element(const char* type) {
        try {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError().clear();
            return reinterpret_cast<xp_element*>(new xaml::Element(xaml::ParseElementType(type)));
        } catch (const std::exception& error) {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError() = error.what();
            return nullptr;
        }
    }

    void ElementAbi::xp_destroy_element(xp_element* element) {
        delete reinterpret_cast<xaml::Element*>(element);
    }

    int ElementAbi::xp_items_remove_item(xp_element* target) {
        try {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError().clear();
            if (target == nullptr) {
                throw std::invalid_argument("target is required");
            }
            return universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::ElementTree::RemoveItem(*reinterpret_cast<xaml::Element*>(target)) ? 1 : 0;
        } catch (const std::exception& error) {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError() = error.what();
            return -1;
        }
    }

    int ElementAbi::xp_add_child(
        xp_element* parent,
        xp_element* child
    ) {
        try {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError().clear();
            if (parent == nullptr || child == nullptr) {
                throw std::invalid_argument("parent and child are required");
            }
            xaml::ValidateChild(
                *reinterpret_cast<const xaml::Element*>(parent),
                *reinterpret_cast<const xaml::Element*>(child));
            reinterpret_cast<xaml::Element*>(parent)->AddChild(
                std::unique_ptr<xaml::Element>(reinterpret_cast<xaml::Element*>(child)));
            return 1;
        } catch (const std::exception& error) {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError() = error.what();
            return 0;
        }
    }

    int ElementAbi::xp_set_attribute(
        xp_element* element,
        const char* name,
        const char* value
    ) {
        try {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError().clear();
            if (element == nullptr) {
                throw std::invalid_argument("element is required");
            }
            xaml::SetAttribute(*reinterpret_cast<xaml::Element*>(element), name, value);
            return 1;
        } catch (const std::exception& error) {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError() = error.what();
            return 0;
        }
    }

    xp_element* ElementAbi::xp_find_element(
        xp_element* root,
        const char* id
    ) {
        try {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError().clear();
            if (root == nullptr || id == nullptr || *id == '\0') {
                throw std::invalid_argument("root and id are required");
            }
            return reinterpret_cast<xp_element*>(universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::ElementTree::FindElement(
                *reinterpret_cast<xaml::Element*>(root), id));
        } catch (const std::exception& error) {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError() = error.what();
            return nullptr;
        }
    }

    int ElementAbi::xp_find_element_count(
        xp_element* root,
        const char* id
    ) {
        try {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError().clear();
            if (root == nullptr || id == nullptr || *id == '\0') {
                throw std::invalid_argument("root and id are required");
            }
            return universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::ElementTree::CountElements(*reinterpret_cast<xaml::Element*>(root), id);
        } catch (const std::exception& error) {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError() = error.what();
            return -1;
        }
    }

    xp_element* ElementAbi::xp_find_element_at(
        xp_element* root,
        const char* id,
        int index
    ) {
        try {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError().clear();
            if (root == nullptr || id == nullptr || *id == '\0' || index < 0) {
                throw std::invalid_argument("root, id and non-negative index are required");
            }
            return reinterpret_cast<xp_element*>(universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::ElementTree::FindElementAt(
                *reinterpret_cast<xaml::Element*>(root), id, index));
        } catch (const std::exception& error) {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError() = error.what();
            return nullptr;
        }
    }

    int ElementAbi::xp_layout(
        xp_element* root,
        float width,
        float height
    ) {
        try {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError().clear();
            if (root == nullptr) {
                throw std::invalid_argument("root is required");
            }
            xaml::layout(*reinterpret_cast<xaml::Element*>(root), {width, height});
            return 1;
        } catch (const std::exception& error) {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError() = error.what();
            return 0;
        }
    }

    xp_element* ElementAbi::xp_hit_test(
        xp_element* root,
        float x,
        float y
    ) {
        try {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError().clear();
            if (root == nullptr) {
                throw std::invalid_argument("root is required");
            }
            return reinterpret_cast<xp_element*>(xaml::HitTest(
                *reinterpret_cast<xaml::Element*>(root), x, y));
        } catch (const std::exception& error) {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError() = error.what();
            return nullptr;
        }
    }

    // Возвращает previewer-у любой видимый элемент под указателем,
    // включая элементы, которые не являются enabled или interactive.

    xp_element* ElementAbi::xp_hit_test_visual(
        xp_element* root,
        float x,
        float y
    ) {
        try {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError().clear();
            if (root == nullptr) {
                throw std::invalid_argument("root is required");
            }
            return reinterpret_cast<xp_element*>(universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::ElementTree::HitTestVisual(
                *reinterpret_cast<xaml::Element*>(root), x, y));
        } catch (const std::exception& error) {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError() = error.what();
            return nullptr;
        }
    }

    int ElementAbi::xp_hit_test_cursor_kind(
        xp_element* root,
        float x,
        float y
    ) {
        try {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError().clear();
            if (root == nullptr) {
                throw std::invalid_argument("root is required");
            }
            auto& nativeRoot = *reinterpret_cast<xaml::Element*>(root);
            xaml::Element* const visual = universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::ElementTree::HitTestVisual(nativeRoot, x, y);
            if (visual == nullptr) {
                return 0;
            }
            xaml::Element* const interactive = xaml::HitTest(nativeRoot, x, y);
            if (interactive != nullptr && interactive->Type() != xaml::ElementType::scrollViewer) {
                return 1;
            }
            for (xaml::Element* element = visual; element != nullptr; element = element->Parent()) {
                if (element->Type() == xaml::ElementType::scrollViewer) {
                    return 2;
                }
            }
            return 0;
        } catch (const std::exception& error) {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError() = error.what();
            return 0;
        }
    }

    // Копирует рассчитанные layout-границы элемента в структуру C bridge.

    int ElementAbi::xp_element_bounds(
        const xp_element* element,
        xp_rect* bounds
    ) {
        try {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError().clear();
            if (element == nullptr || bounds == nullptr) {
                throw std::invalid_argument("element and bounds are required");
            }
            const xaml::Rect elementBounds = reinterpret_cast<const xaml::Element*>(element)->Bounds();
            *bounds = {elementBounds.x, elementBounds.y, elementBounds.width, elementBounds.height};
            return 1;
        } catch (const std::exception& error) {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError() = error.what();
            return 0;
        }
    }

    int ElementAbi::xp_get_scroll_offsets(
        xp_element* root,
        const char* scrollViewerId,
        float* horizontalOffset,
        float* verticalOffset
    ) {
        try {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError().clear();
            if (root == nullptr || scrollViewerId == nullptr || *scrollViewerId == '\0'
                || horizontalOffset == nullptr || verticalOffset == nullptr) {
                throw std::invalid_argument("root, scroll viewer id and offsets are required");
            }
            xaml::Element* const scrollViewer = universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::ElementTree::FindElement(
                *reinterpret_cast<xaml::Element*>(root), scrollViewerId);
            if (scrollViewer == nullptr || scrollViewer->Type() != xaml::ElementType::scrollViewer) {
                return 0;
            }
            *horizontalOffset = scrollViewer->HorizontalOffset();
            *verticalOffset = scrollViewer->VerticalOffset();
            return 1;
        } catch (const std::exception& error) {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError() = error.what();
            return 0;
        }
    }

    int ElementAbi::xp_set_scroll_offsets(
        xp_element* root,
        const char* scrollViewerId,
        float horizontalOffset,
        float verticalOffset
    ) {
        try {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError().clear();
            if (root == nullptr || scrollViewerId == nullptr || *scrollViewerId == '\0'
                || !std::isfinite(horizontalOffset) || !std::isfinite(verticalOffset)) {
                throw std::invalid_argument("root, scroll viewer id and finite offsets are required");
            }
            xaml::Element* const scrollViewer = universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::ElementTree::FindElement(
                *reinterpret_cast<xaml::Element*>(root), scrollViewerId);
            if (scrollViewer == nullptr || scrollViewer->Type() != xaml::ElementType::scrollViewer) {
                return 0;
            }
            scrollViewer->SetHorizontalOffset(horizontalOffset);
            scrollViewer->SetVerticalOffset(verticalOffset);
            return 1;
        } catch (const std::exception& error) {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError() = error.what();
            return 0;
        }
    }

    int ElementAbi::xp_scroll_by(
        xp_element* root,
        float x,
        float y,
        float horizontalDelta,
        float verticalDelta
    ) {
        try {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError().clear();
            if (root == nullptr || !std::isfinite(horizontalDelta) || !std::isfinite(verticalDelta)) {
                throw std::invalid_argument("root and finite deltas are required");
            }
            xaml::Element* element = universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::ElementTree::FindScrollViewer(
                *reinterpret_cast<xaml::Element*>(root), x, y);
            if (element == nullptr) {
                return 0;
            }
            const float horizontalOffset = std::clamp(
                element->HorizontalOffset() + horizontalDelta,
                0.0f,
                std::max(0.0f, element->Extent().width - element->Viewport().width));
            const float verticalOffset = std::clamp(
                element->VerticalOffset() + verticalDelta,
                0.0f,
                std::max(0.0f, element->Extent().height - element->Viewport().height));
            const bool changed = horizontalOffset != element->HorizontalOffset()
                || verticalOffset != element->VerticalOffset();
            if (!changed) {
                return 0;
            }
            element->SetHorizontalOffset(horizontalOffset);
            element->SetVerticalOffset(verticalOffset);
            return 1;
        } catch (const std::exception& error) {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError() = error.what();
            return 0;
        }
    }

    const char* ElementAbi::xp_element_id(const xp_element* element) {
        if (element == nullptr) {
            return "";
        }
        return reinterpret_cast<const xaml::Element*>(element)->Id().c_str();
    }
} // namespace universaldevkit::windows::androidapppreviewerpluginsdk::internal::abi