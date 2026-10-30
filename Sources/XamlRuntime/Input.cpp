#include "../../Includes/XamlRuntime/UniversalDevKit/XamlRuntime/Input.h"

#include <UniversalDevKit/Diagnostic/Logging.h>

#include "../../Includes/XamlRuntime/UniversalDevKit/XamlRuntime/VisualState.h"

namespace universaldevkit::xamlruntime::details {
    bool Contains(const Rect& bounds, float x, float y) {
        return universaldevkit::helpers::math::Geometry::Contains(bounds, x, y);
    }

    bool HasIntrinsicInteraction(const Element& element) {
        switch (element.Type()) {
        case ElementType::button:
        case ElementType::iconButton:
        case ElementType::toggleSwitch:
            return true;
        default:
            return false;
        }
    }

    struct HitTestResult {
        Element* interactive = nullptr;
        bool blocksInput = false;
    };

    HitTestResult HitTestElement(Element& element, float x, float y, float offsetX, float offsetY) {
        const VisualTransform defaults{};
        const auto& transform = element.States().Contains<VisualTransform>()
            ? element.State<VisualTransform>() : defaults;
        const float renderedOffsetX = offsetX + element.RenderOffsetX() + transform.offsetX;
        const float renderedOffsetY = offsetY + element.RenderOffsetY() + transform.offsetY;
        if (!element.CanReceiveInput()
            || !element.IsEnabled()
            || !Contains(element.ClipBounds(), x - renderedOffsetX, y - renderedOffsetY)) {
            return {};
        }

        const float childrenOffsetX = element.Type() == ElementType::scrollViewer
            ? renderedOffsetX - element.HorizontalOffset() : renderedOffsetX;
        const float childrenOffsetY = element.Type() == ElementType::scrollViewer
            ? renderedOffsetY - element.VerticalOffset() : renderedOffsetY;
        std::vector<std::unique_ptr<Element>>& children = element.Children();
        bool childBlocksInput = false;
        for (auto child = children.rbegin(); child != children.rend(); ++child) {
            const HitTestResult hit = HitTestElement(**child, x, y, childrenOffsetX, childrenOffsetY);
            if (hit.interactive != nullptr) {
                return hit;
            }
            if (hit.blocksInput) {
                childBlocksInput = true;
                break;
            }
        }
        const bool containsPointer = Contains(
            element.Bounds(), x - renderedOffsetX, y - renderedOffsetY);
        if (!containsPointer) {
            return {};
        }
        if (IsInteractive(element)) {
            return {&element, true};
        }
        // An opaque visual surface sits above its siblings and must prevent
        // their commands from receiving input through it.
        return {nullptr, childBlocksInput || element.Background().alpha > 0.0f};
    }

    Element* HitTestVisualElement(Element& element, float x, float y, float offsetX, float offsetY) {
        const VisualTransform defaults{};
        const auto& transform = element.States().Contains<VisualTransform>()
            ? element.State<VisualTransform>() : defaults;
        const float renderedOffsetX = offsetX + element.RenderOffsetX() + transform.offsetX;
        const float renderedOffsetY = offsetY + element.RenderOffsetY() + transform.offsetY;
        if (element.VisibilityValue() != attr::Visibility::visible
            || !Contains(element.ClipBounds(), x - renderedOffsetX, y - renderedOffsetY)) {
            return nullptr;
        }

        const float childrenOffsetX = element.Type() == ElementType::scrollViewer
            ? renderedOffsetX - element.HorizontalOffset() : renderedOffsetX;
        const float childrenOffsetY = element.Type() == ElementType::scrollViewer
            ? renderedOffsetY - element.VerticalOffset() : renderedOffsetY;
        std::vector<std::unique_ptr<Element>>& children = element.Children();
        for (auto child = children.rbegin(); child != children.rend(); ++child) {
            if (Element* const hit = HitTestVisualElement(**child, x, y, childrenOffsetX, childrenOffsetY)) {
                return hit;
            }
        }
        return Contains(element.Bounds(), x - renderedOffsetX, y - renderedOffsetY) ? &element : nullptr;
    }
}

namespace universaldevkit::xamlruntime {
    bool IsInteractive(const Element& element) {
        return details::HasIntrinsicInteraction(element) || element.HasCommand();
    }

    Element* HitTest(Element& root, float x, float y) {
        return details::HitTestElement(root, x, y, 0.0f, 0.0f).interactive;
    }

    Element* HitTestVisual(Element& root, float x, float y) {
        return details::HitTestVisualElement(root, x, y, 0.0f, 0.0f);
    }

    bool HandleTap(Element& element) {
        if (!IsInteractive(element)) {
            return false;
        }
        if (element.Type() == ElementType::toggleSwitch) {
            element.SetIsOn(!element.IsOn());
            UDK_LOG_DEBUG(
                "XamlRuntime.Input",
                "Toggle tap: element='{}', isOn={}",
                element.Id(),
                element.IsOn());
            return true;
        }
        if (element.HasCommand()) {
            UDK_LOG_DEBUG(
                "XamlRuntime.Input",
                "Tap: element='{}'",
                element.Id());
            element.ExecuteCommand();
        }
        return true;
    }
}