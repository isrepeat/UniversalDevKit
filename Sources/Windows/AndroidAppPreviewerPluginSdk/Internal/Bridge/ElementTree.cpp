#include "Internal/Bridge/ElementTree.h"

#include <filesystem>
#include <algorithm>
#include <cctype>

namespace universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::details {
    bool ContainsPoint(float left, float top, float width, float height, float x, float y) {
        return x >= left && x <= left + width && y >= top && y <= top + height;
    }
}

namespace universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge {
    //
    // Методы
    //
    xaml::Element* ElementTree::FindElement(
        xaml::Element& element,
        std::string_view id) {
        if (element.Id() == id) {
            return &element;
        }
        for (const auto& child : element.Children()) {
            if (xaml::Element* const found = FindElement(*child, id)) {
                return found;
            }
        }
        return nullptr;
    }

    int ElementTree::CountElements(
        const xaml::Element& element,
        std::string_view id) {
        int count = element.Id() == id ? 1 : 0;
        for (const auto& child : element.Children()) {
            count += CountElements(*child, id);
        }
        return count;
    }

    xaml::Element* ElementTree::FindElementAt(
        xaml::Element& element,
        std::string_view id,
        int& index) {
        if (element.Id() == id) {
            if (index == 0) {
                return &element;
            }
            --index;
        }
        for (const auto& child : element.Children()) {
            if (xaml::Element* const found = FindElementAt(*child, id, index)) {
                return found;
            }
        }
        return nullptr;
    }

    xaml::Element* ElementTree::FindElementAtSource(
        xaml::Element& element,
        std::string_view sourcePath,
        int line,
        int column) {
        // Редактор передаёт путь со слешами '/', а generated XAML на Windows
        // может хранить '\\'. Сопоставляем нормализованные пути без учёта регистра.
        if (SameSourcePath(element.SourcePath(), sourcePath)
            && element.SourceLine() == line
            && element.SourceColumn() == column) {
            return &element;
        }
        for (const auto& child : element.Children()) {
            if (xaml::Element* const candidate = FindElementAtSource(*child, sourcePath, line, column)) {
                return candidate;
            }
        }
        return nullptr;
    }

    xaml::Element* ElementTree::HitTestVisual(
        xaml::Element& element,
        float x,
        float y,
        float offsetX,
        float offsetY) {
        const xaml::Rect& clipBounds = element.ClipBounds();
        if (element.VisibilityValue() != xaml::attr::Visibility::visible
            || !details::ContainsPoint(
                clipBounds.x, clipBounds.y, clipBounds.width, clipBounds.height, x - offsetX, y - offsetY)) {
            return nullptr;
        }

        const auto& children = element.Children();
        const float childrenOffsetX = element.Type() == xaml::ElementType::scrollViewer
            ? offsetX - element.HorizontalOffset() : offsetX;
        const float childrenOffsetY = element.Type() == xaml::ElementType::scrollViewer
            ? offsetY - element.VerticalOffset() : offsetY;
        for (auto child = children.rbegin(); child != children.rend(); ++child) {
            if (xaml::Element* const hit = HitTestVisual(**child, x, y, childrenOffsetX, childrenOffsetY)) {
                return hit;
            }
        }

        const xaml::Rect& bounds = element.Bounds();
        return details::ContainsPoint(
            bounds.x, bounds.y, bounds.width, bounds.height, x - offsetX, y - offsetY) ? &element : nullptr;
    }

    xaml::Element* ElementTree::FindScrollViewer(
        xaml::Element& root,
        float x,
        float y) {
        xaml::Element* element = HitTestVisual(root, x, y);
        while (element != nullptr && element->Type() != xaml::ElementType::scrollViewer) {
            element = element->Parent();
        }
        return element;
    }

    bool ElementTree::RemoveItem(xaml::Element& target) {
        xaml::Element* item = &target;
        for (xaml::Element* parent = item->Parent(); parent != nullptr; parent = parent->Parent()) {
            if (parent->Type() == xaml::ElementType::listView) {
                parent->RemoveChildImmediately(*item);
                return true;
            }
            item = parent;
        }
        return false;
    }

    //
    // Internal
    //
    bool ElementTree::SameSourcePath(
        std::string_view left,
        std::string_view right) {
        const std::string normalizedLeft = std::filesystem::path(left).lexically_normal().generic_string();
        const std::string normalizedRight = std::filesystem::path(right).lexically_normal().generic_string();
        return normalizedLeft.size() == normalizedRight.size()
            && std::equal(normalizedLeft.begin(), normalizedLeft.end(), normalizedRight.begin(), [](char first, char second) {
                return std::tolower(static_cast<unsigned char>(first)) == std::tolower(static_cast<unsigned char>(second));
            });
    }
}