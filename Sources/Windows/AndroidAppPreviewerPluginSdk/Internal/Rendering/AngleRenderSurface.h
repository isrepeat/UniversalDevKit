#pragma once
#include <UniversalDevKit/XamlRuntime/Config.h>

#include <string_view>
#include <functional>
#include <memory>

namespace universaldevkit::xamlruntime {
    class Element;
    class IRenderBackend;
}

namespace universaldevkit::windows::androidapppreviewerpluginsdk::internal::rendering {
    //
    // Изолирует EGL pbuffer и OpenGL ES ресурсы от C ABI native bridge.
    //
    class AngleRenderSurface {
    public:
        AngleRenderSurface(
            int width,
            int height,
            std::string_view fontPath,
            std::string_view resourceRoot);
        ~AngleRenderSurface();

        AngleRenderSurface(const AngleRenderSurface&) = delete;
        AngleRenderSurface& operator=(const AngleRenderSurface&) = delete;

        void Render(
            xaml::Element& root,
            unsigned char* destination,
            int destinationStride);
        void Render(
            const std::function<void(xaml::IRenderBackend&)>& draw,
            unsigned char* destination,
            int destinationStride);

    private:
        class Implementation;

    private:
        std::unique_ptr<Implementation> implementation;
    };
}