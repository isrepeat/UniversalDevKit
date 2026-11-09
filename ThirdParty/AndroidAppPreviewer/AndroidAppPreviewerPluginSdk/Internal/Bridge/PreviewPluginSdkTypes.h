#pragma once
#include <UniversalDevKit/XamlRuntime/InteractionController.h>
#include <UniversalDevKit/XamlRuntime/ScrollController.h>
#include <UniversalDevKit/XamlRuntime/XamlLayout.h>
#include <UniversalDevKit/XamlRuntime/Animation.h>
#include <AndroidAppPreviewerPluginSdk/Session/PreviewSessionBase.h>
#include <AndroidAppPreviewerPluginSdk/AndroidAppPreviewerPlugin.h>

#include "Internal/Rendering/AngleRenderSurface.h"

#include <memory>

namespace universaldevkit::windows::androidapppreviewerpluginsdk {
    struct xp_session {
        explicit xp_session(int width, int height);

        std::unique_ptr<universaldevkit::windows::androidapppreviewerpluginsdk::session::PreviewSessionBase> previewSession;
        universaldevkit::windows::androidapppreviewerpluginsdk::session::PreviewSessionBase& value;
        xaml::Element* inspectionElement = nullptr;
        std::weak_ptr<void> inspectionElementLifetime;
        xaml::Element* selectedElement = nullptr;
        std::weak_ptr<void> selectedElementLifetime;
        xaml::attr::Wireframe inspectionWireframe{
            3.0f,
            xaml::attr::WireframeLineStyle::solid,
            {0.878f, 0.322f, 0.322f, 1.0f},
        };
        xaml::attr::Wireframe selectedWireframe{
            3.0f,
            xaml::attr::WireframeLineStyle::solid,
            {0.30f, 0.64f, 1.0f, 1.0f},
        };
    };

    struct xp_angle_surface {
        explicit xp_angle_surface(
            int width,
            int height,
            const char* fontPath,
            const char* resourceRoot);

        int width;
        int height;
        universaldevkit::windows::androidapppreviewerpluginsdk::internal::rendering::AngleRenderSurface value;
    };

    struct xp_animation_controller {
        xaml::AnimationController value;
        xaml::ScrollController scrollController;
    };

    struct xp_interaction_controller {
        xaml::InteractionController value;
    };
}