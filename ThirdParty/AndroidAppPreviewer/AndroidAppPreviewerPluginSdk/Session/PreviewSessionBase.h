#pragma once
#include "../Export.h"
#include <UniversalDevKit/XamlRuntime/RenderEngine.h>
#include <AndroidAppPreviewerPluginSdk/Session/PreviewNavigationController.h>

#include <string_view>
#include <memory>
#include <string>
#include <vector>
#include <span>

namespace universaldevkit::windows::androidapppreviewerpluginsdk::session {
    struct PreviewRoute final {
        std::string_view id;
        std::string_view source;
        std::string_view target;
        std::string_view backwardOfRouteId;
        std::string_view title;
        bool isDefault;
        bool isPreviousPage;
        std::string_view dataType;
        bool hasPreviewDefaultNavigationState;
    };

    class UNIVERSALDEVKIT_ANDROIDAPPPREVIEWERPLUGINSDK_API PreviewSessionBase {
    public:
        PreviewSessionBase();
        virtual ~PreviewSessionBase();
        PreviewSessionBase(const PreviewSessionBase&) = delete;
        PreviewSessionBase& operator=(const PreviewSessionBase&) = delete;

        virtual xaml::Element& Root() = 0;
        virtual std::string_view CurrentPage() const = 0;
        virtual std::string_view LayoutRootPage() const = 0;
        virtual std::string_view PageTitle(std::string_view page) const = 0;
        virtual std::vector<PreviewRoute> Routes() const = 0;
        virtual bool IsTransitioning() const = 0;
        virtual bool Navigate(std::span<const std::string_view> transitionIds, std::string& error) = 0;
        virtual bool LoadPage(std::string_view page) = 0;
        virtual void Resize(int width, int height) = 0;
        virtual bool ReloadMarkup(
            std::string_view page,
            std::string_view markup,
            std::string_view sourcePath,
            std::string& error
        ) = 0;
        virtual void SetAnimationPlaybackRate(float value) = 0;
        virtual bool ApplyScenario(std::string_view page, std::string_view json);
        virtual void PointerDown(float x, float y) = 0;
        virtual void PointerMove(float x, float y) = 0;
        virtual void PointerUp(float x, float y) = 0;
        virtual void CancelPointer() = 0;
        virtual bool Update() = 0;
        virtual void Render(xaml::IRenderBackend& renderBackendImpl) = 0;

        PreviewNavigationController& Navigation();
        static std::vector<std::string> ParseNavigationTransitionIds(std::string_view json);

    private:
        PreviewNavigationController previewNavigationController;
    };
}