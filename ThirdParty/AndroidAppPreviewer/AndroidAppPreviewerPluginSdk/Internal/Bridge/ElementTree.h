#pragma once
#include <UniversalDevKit/XamlRuntime/XamlLayout.h>

#include <string_view>

namespace universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge {
    class ElementTree final {
    public:
        ElementTree() = delete;

        static xaml::Element* FindElement(
            xaml::Element& element,
            std::string_view id);
        static int CountElements(
            const xaml::Element& element,
            std::string_view id);
        static xaml::Element* FindElementAt(
            xaml::Element& element,
            std::string_view id,
            int& index);
        static xaml::Element* FindElementAtSource(
            xaml::Element& element,
            std::string_view sourcePath,
            int line,
            int column);
        static xaml::Element* HitTestVisual(
            xaml::Element& element,
            float x,
            float y,
            float offsetX = 0.0f,
            float offsetY = 0.0f);
        static xaml::Element* FindScrollViewer(
            xaml::Element& root,
            float x,
            float y);
        static bool RemoveItem(xaml::Element& target);

    private:
        static bool SameSourcePath(
            std::string_view left,
            std::string_view right);
    };
}