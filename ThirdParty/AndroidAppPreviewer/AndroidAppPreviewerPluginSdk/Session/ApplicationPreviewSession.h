#pragma once
#include <AndroidAppPreviewerPluginSdk/Session/PreviewSessionBase.h>

#include <stdexcept>

namespace universaldevkit::windows::androidapppreviewerpluginsdk::session {
    // Адаптер общего жизненного цикла приложения. Прикладные preview-сессии
    // наследуют его и переопределяют только необходимые точки расширения.
    template <typename TApplicationSession>
    class ApplicationPreviewSession : public PreviewSessionBase {
    public:
        ApplicationPreviewSession(int width, int height) {
            if (width <= 0 || height <= 0) {
                throw std::invalid_argument("Preview session dimensions must be positive");
            }
            this->applicationSession.Initialize({static_cast<float>(width), static_cast<float>(height)});
            this->initialPageName = this->applicationSession.Pages().CurrentPageName();
        }

        //
        // PreviewSessionBase
        //
        xaml::Element& Root() override {
            return this->applicationSession.Root();
        }

        std::string_view CurrentPage() const override {
            return this->applicationSession.Pages().CurrentPageName();
        }

        std::string_view LayoutRootPage() const override {
            return this->initialPageName;
        }

        std::string_view PageTitle(std::string_view page) const override {
            return this->applicationSession.Pages().PageTitle(page);
        }

        std::vector<PreviewRoute> Routes() const override {
            std::vector<PreviewRoute> result;
            for (const auto& route : this->applicationSession.Pages().preview_Routes()) {
                result.push_back({
                    route.id, route.source, route.target, route.backwardOfRouteId, route.title,
                    route.isDefault, route.targetKind == decltype(route.targetKind)::previousPage,
                    route.dataType, route.hasPreviewDefaultNavigationState
                });
            }
            return result;
        }

        bool IsTransitioning() const override {
            return this->applicationSession.Pages().IsTransitioning();
        }

        bool Navigate(std::span<const std::string_view> transitionIds, std::string& error) override {
            return this->applicationSession.Pages().preview_NavigateTransitions(transitionIds, error);
        }

        bool LoadPage(std::string_view page) override {
            return this->applicationSession.Pages().Navigate(page);
        }

        void Resize(int width, int height) override {
            if (width <= 0 || height <= 0) {
                throw std::invalid_argument("Preview session dimensions must be positive");
            }
            this->applicationSession.Resize({static_cast<float>(width), static_cast<float>(height)});
        }

        bool ReloadMarkup(
            std::string_view page,
            std::string_view markup,
            std::string_view sourcePath,
            std::string& error
        ) override {
            return this->applicationSession.Pages().preview_ReloadMarkup(page, markup, sourcePath, error);
        }

        void SetAnimationPlaybackRate(float value) override {
            this->applicationSession.Pages().SetAnimationPlaybackRate(value);
            this->OnPlaybackRateChanged(value);
        }

        void PointerDown(float x, float y) override {
            this->applicationSession.PointerDown(x, y);
        }

        void PointerMove(float x, float y) override {
            this->applicationSession.PointerMove(x, y);
        }

        void PointerUp(float x, float y) override {
            this->applicationSession.PointerUp(x, y);
        }

        void CancelPointer() override {
            this->applicationSession.CancelPointer();
        }

        bool Update() final {
            const bool changed = this->BeforeUpdate();
            return this->applicationSession.Update() || changed;
        }

        void Render(xaml::IRenderBackend& renderBackendImpl) final {
            this->RenderBackground(renderBackendImpl);
            this->applicationSession.Render(renderBackendImpl);
            this->AfterRender();
        }

        const auto& Pages() const {
            return this->applicationSession.Pages();
        }

    protected:
        TApplicationSession& Application() {
            return this->applicationSession;
        }

        virtual bool BeforeUpdate() {
            return false;
        }

        virtual void RenderBackground(xaml::IRenderBackend&) {
        }

        virtual void AfterRender() {
        }

        virtual void OnPlaybackRateChanged(float) {
        }

    private:
        TApplicationSession applicationSession;
        std::string initialPageName;
    };
}