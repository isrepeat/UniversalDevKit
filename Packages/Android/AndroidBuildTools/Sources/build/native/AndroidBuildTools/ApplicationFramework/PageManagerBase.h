#pragma once
#include <UniversalDevKit/XamlRuntime/RenderEngine.h>
#if defined(ANDROID_APP_PREVIEWER)
#include <UniversalDevKit/XamlRuntime/RuntimeMarkup/RuntimeTreeBuilder.h>
#include <UniversalDevKit/XamlRuntime/RuntimeMarkup/XamlParser.h>
#endif

#include "InputDispatcher.h"

#include <algorithm>
#include <stdexcept>
#include <chrono>
#include <limits>
#include <vector>
#include <span>

namespace application_framework {
    template <typename TTraits>
    class PageManagerBase : public TTraits::PageNavigator {
    public:
        using Page = typename TTraits::Page;
        using NavigationStateBase = typename TTraits::NavigationStateBase;
        using NavigationTrigger = typename TTraits::NavigationTrigger;
        using NavigationTargetKind = typename TTraits::NavigationTargetKind;
        using NavigationRequest = typename TTraits::NavigationRequest;
        using NavigationDataContract = typename TTraits::NavigationDataContract;
        using PageContext = typename TTraits::PageContext;
        using ApplicationRepository = typename TTraits::ApplicationRepository;
        using AppSessionController = typename TTraits::AppSessionController;
#if defined(ANDROID_APP_PREVIEWER)
        struct preview_Route final {
            std::string_view id;
            std::string_view source;
            std::string_view target;
            std::string_view backwardOfRouteId;
            std::string_view title;
            bool isDefault;
            NavigationTargetKind targetKind;
            std::string_view dataType;
            bool hasPreviewDefaultNavigationState;
        };
#endif

        PageManagerBase(ApplicationRepository& applicationRepository, AppSessionController& appSessionController);
        virtual ~PageManagerBase() = default;
        PageManagerBase(const PageManagerBase&) = delete;
        PageManagerBase& operator=(const PageManagerBase&) = delete;

        //
        // IPageNavigator
        //
        bool Navigate(std::string_view pageName) override;
        bool Trigger(NavigationTrigger trigger) override;
        bool Trigger(NavigationTrigger trigger, std::unique_ptr<NavigationStateBase> navigationState) override;
        bool NavigateBack(std::unique_ptr<NavigationStateBase> result = {}) override;

        void Initialize(xaml::Size size);
        void Resize(xaml::Size size);
        std::string_view CurrentPageName() const;
        std::string_view PageTitle(std::string_view name) const;
        xaml::Element& Root();
        bool IsTransitioning() const;
        void Render(xaml::IRenderBackend& renderBackendImpl, const xaml::RendererRegistry& rendererRegistry);
        void PointerDown(float x, float y);
        void PointerMove(float x, float y);
        void PointerUp(float x, float y);
        void CancelPointer();
        bool Update();
        void SetAnimationPlaybackRate(float value);
#if defined(ANDROID_APP_PREVIEWER)
        std::vector<preview_Route> preview_Routes() const;
        bool preview_NavigateTransitions(std::span<const std::string_view> ids, std::string& error);
        bool preview_ReloadMarkup(std::string_view page, std::string_view markup, std::string_view sourcePath, std::string& error);
#endif

    protected:
        struct NavigationRoute final {
            std::string_view id;
            std::string_view source;
            NavigationTrigger trigger;
            std::string_view target;
            NavigationTargetKind targetKind;
            const NavigationDataContract* dataContract;
            std::string_view title;
        };
        struct HistoryEntry final {
            Page* page;
            const NavigationRoute* incomingRoute;
        };
        virtual std::span<const NavigationRoute> Routes() const = 0;
        virtual bool CanNavigate(const NavigationRoute&) const {
            return true;
        }

    private:
        std::string_view ResolveTarget(const NavigationRoute& navigationRoute) const;
        bool Navigate(const NavigationRoute& navigationRoute, std::unique_ptr<NavigationStateBase> navigationState);
        static bool IsNavigationDataValid(const NavigationRoute& navigationRoute, const NavigationStateBase* navigationState);
        void AttachAnimations();
        void UpdateTransition();

    private:
        PageContext pageContext;
        typename TTraits::PageRegistry pageRegistry;
        Page* currentPage = nullptr;
        Page* outgoingPage = nullptr;
        std::vector<HistoryEntry> history;
        xaml::Size viewport{};
        xaml::AnimationController animationController;
        InputDispatcher inputDispatcher;
        float playbackRate = 1.0f;
        bool navigating = false;
        bool dirty = true;
    };
}

namespace application_framework {
    template <typename TTraits>
    PageManagerBase<TTraits>::PageManagerBase(ApplicationRepository& applicationRepository, AppSessionController& appSessionController)
        : pageContext{*this, applicationRepository, appSessionController, appSessionController}
        , pageRegistry(this->pageContext) {
    }

    //
    // IPageNavigator
    //
    template <typename TTraits>
    bool PageManagerBase<TTraits>::Navigate(std::string_view pageName) {
        if (this->currentPage == nullptr) {
            return false;
        }
        if (pageName == this->CurrentPageName()) {
            return true;
        }
        for (const auto& navigationRoute : this->Routes()) {
            if (navigationRoute.source == this->CurrentPageName() && this->ResolveTarget(navigationRoute) == pageName) {
                return this->Navigate(navigationRoute, {});
            }
        }
        return false;
    }

    template <typename TTraits>
    bool PageManagerBase<TTraits>::Trigger(NavigationTrigger trigger) {
        return this->Trigger(trigger, {});
    }

    template <typename TTraits>
    bool PageManagerBase<TTraits>::Trigger(NavigationTrigger trigger, std::unique_ptr<NavigationStateBase> navigationState) {
        for (const auto& navigationRoute : this->Routes()) {
            if (navigationRoute.source == this->CurrentPageName() && navigationRoute.trigger == trigger) {
                return this->Navigate(navigationRoute, std::move(navigationState));
            }
        }
        return false;
    }

    template <typename TTraits>
    bool PageManagerBase<TTraits>::NavigateBack(std::unique_ptr<NavigationStateBase> result) {
        return this->Trigger(NavigationTrigger::navigateBack, std::move(result));
    }

    //
    // API
    //
    template <typename TTraits>
    void PageManagerBase<TTraits>::Initialize(xaml::Size size) {
        if (size.width <= 0 || size.height <= 0) {
            throw std::invalid_argument("Viewport dimensions must be positive");
        }
        if (this->currentPage != nullptr) {
            this->Resize(size);
            return;
        }
        this->viewport = size;
        this->pageRegistry.ForEach([size](Page& page) { page.Initialize(size); });
        this->currentPage = this->pageRegistry.Find(TTraits::InitialPageName());
        const NavigationRequest navigationRequest{{}, this->currentPage->Name(), NavigationTrigger::navigateBack};
        if (!this->currentPage->OnNavigatingTo(navigationRequest, {})) {
            throw std::runtime_error("Initial page rejected activation");
        }
        this->history.push_back({this->currentPage, nullptr});
        this->AttachAnimations();
    }

    template <typename TTraits>
    void PageManagerBase<TTraits>::Resize(xaml::Size size) {
        if (size.width <= 0 || size.height <= 0) {
            throw std::invalid_argument("Viewport dimensions must be positive");
        }
        this->viewport = size;
        this->pageRegistry.ForEach([size](Page& page) { xaml::layoutInViewport(page.Root(), size); });
        this->dirty = true;
    }

    template <typename TTraits>
    std::string_view PageManagerBase<TTraits>::CurrentPageName() const {
        return this->currentPage == nullptr ? std::string_view{} : this->currentPage->Name();
    }

    template <typename TTraits>
    std::string_view PageManagerBase<TTraits>::PageTitle(std::string_view name) const {
        const auto* page = this->pageRegistry.Find(name);
        return page == nullptr ? std::string_view{} : page->Title();
    }

    template <typename TTraits>
    xaml::Element& PageManagerBase<TTraits>::Root() {
        if (this->currentPage == nullptr) {
            throw std::logic_error("Application session is not initialized");
        }
        return this->currentPage->Root();
    }

    template <typename TTraits>
    void PageManagerBase<TTraits>::PointerDown(float x, float y) {
        if (this->IsTransitioning()) {
            return;
        }
        this->inputDispatcher.PointerDown(this->Root(), this->animationController, x, y);
    }

    template <typename TTraits>
    void PageManagerBase<TTraits>::PointerMove(float x, float y) {
        if (this->IsTransitioning()) {
            return;
        }
        this->inputDispatcher.PointerMove(x, y);
    }

    template <typename TTraits>
    void PageManagerBase<TTraits>::PointerUp(float x, float y) {
        if (this->IsTransitioning()) {
            return;
        }
        this->inputDispatcher.PointerUp(this->Root(), this->animationController, x, y);
    }

    template <typename TTraits>
    void PageManagerBase<TTraits>::CancelPointer() {
        this->inputDispatcher.Cancel();
    }

    template <typename TTraits>
    bool PageManagerBase<TTraits>::Update() {
        const bool interacting = this->inputDispatcher.Update();
        const bool animating = this->animationController.IsAnimating();
        this->animationController.Update();
        this->UpdateTransition();
        if (this->outgoingPage != nullptr) {
            this->outgoingPage->Update();
            xaml::layoutInViewport(this->outgoingPage->Root(), this->viewport);
        }
        this->currentPage->Update();
        xaml::layoutInViewport(this->Root(), this->viewport);
        const bool changed = this->dirty || interacting || animating || this->animationController.IsAnimating();
        this->dirty = false;
        return changed;
    }

    template <typename TTraits>
    void PageManagerBase<TTraits>::SetAnimationPlaybackRate(float value) {
        this->playbackRate = value;
        this->animationController.SetPlaybackRate(value);
    }

    template <typename TTraits>
    bool PageManagerBase<TTraits>::IsTransitioning() const {
        return this->outgoingPage != nullptr;
    }

    template <typename TTraits>
    void PageManagerBase<TTraits>::Render(xaml::IRenderBackend& renderBackendImpl, const xaml::RendererRegistry& rendererRegistry) {
        if (this->outgoingPage != nullptr) {
            xaml::Render(this->outgoingPage->Root(), renderBackendImpl, rendererRegistry);
        }
        xaml::Render(this->Root(), renderBackendImpl, rendererRegistry);
    }

#if defined(ANDROID_APP_PREVIEWER)
    template <typename TTraits>
    std::vector<typename PageManagerBase<TTraits>::preview_Route> PageManagerBase<TTraits>::preview_Routes() const {
        std::vector<preview_Route> result;
        for (const auto& navigationRoute : this->Routes()) {
            if (navigationRoute.targetKind == NavigationTargetKind::previousPage) {
                // Граф показывает обратные рёбра для входящих маршрутов. Выполнение
                // всегда использует фактическую историю, а не цель из графа.
                for (const auto& incoming : this->Routes()) {
                    if (incoming.targetKind == NavigationTargetKind::page && incoming.target == navigationRoute.source) {
                        result.push_back({navigationRoute.id, navigationRoute.source, incoming.source, incoming.id, navigationRoute.title,
                            true, navigationRoute.targetKind, {}, true});
                    }
                }
            } else {
                const auto* contract = navigationRoute.dataContract;
                result.push_back({
                    navigationRoute.id, navigationRoute.source, navigationRoute.target, {},
                    navigationRoute.title, true, navigationRoute.targetKind,
                    contract == nullptr ? std::string_view{} : contract->typeId,
                    contract == nullptr || !contract->isRequired || contract->preview_CreatePreviewDefaultFn != nullptr});
            }
        }
        return result;
    }

    template <typename TTraits>
    bool PageManagerBase<TTraits>::preview_NavigateTransitions(std::span<const std::string_view> ids, std::string& error) {
        if (ids.empty() || this->IsTransitioning()) {
            error = "Navigation requires transition IDs and an idle page";
            return false;
        }
        // Проверяем весь путь до первого изменения страниц и истории.
        std::vector<std::string_view> simulated;
        for (const auto& entry : this->history) {
            simulated.push_back(entry.page->Name());
        }
        std::vector<const NavigationRoute*> routes;
        std::vector<std::unique_ptr<NavigationStateBase>> states;
        for (const auto id : ids) {
            const auto available = this->Routes();
            const auto found = std::find_if(available.begin(), available.end(), [id](const auto& navigationRoute) { return navigationRoute.id == id; });
            if (found == available.end() || simulated.empty() || found->source != simulated.back()) {
                error = "Transition is not available on the current page";
                return false;
            }
            std::unique_ptr<NavigationStateBase> navigationState;
            if (found->dataContract != nullptr && found->dataContract->preview_CreatePreviewDefaultFn != nullptr) {
                navigationState = found->dataContract->preview_CreatePreviewDefaultFn();
            }
            if (!this->IsNavigationDataValid(*found, navigationState.get())) {
                error = "Native preview default does not satisfy the data contract";
                return false;
            }
            if (found->targetKind == NavigationTargetKind::previousPage) {
                if (simulated.size() < 2) {
                    error = "Navigation history has no previous page";
                    return false;
                }
                simulated.pop_back();
            } else {
                simulated.push_back(found->target);
            }
            routes.push_back(&*found);
            states.push_back(std::move(navigationState));
        }
        for (size_t i = 0; i < routes.size(); ++i) {
            if (!this->Navigate(*routes[i], std::move(states[i]))) {
                error = "Page lifecycle rejected navigation";
                return false;
            }
            if (i + 1 < routes.size() && this->IsTransitioning()) {
                // Промежуточные страницы пути графа доводим до конечного состояния;
                // последний переход проигрывается обычным циклом кадров.
                const auto elapsed = std::chrono::duration<float, std::milli>(std::numeric_limits<float>::max());
                xaml::AnimationController::Update(this->outgoingPage->Root(), elapsed);
                xaml::AnimationController::Update(this->Root(), elapsed);
                this->UpdateTransition();
            }
        }
        error.clear();
        return true;
    }

    template <typename TTraits>
    bool PageManagerBase<TTraits>::preview_ReloadMarkup(std::string_view page, std::string_view markup, std::string_view sourcePath, std::string& error) {
        auto* target = this->pageRegistry.Find(page);
        if (target == nullptr) {
            error = "Unknown page";
            return false;
        }
        auto tree = xaml::runtime::RuntimeTreeBuilder{}.BuildPage(
            xaml::runtime::XamlParser{}.Parse(markup, sourcePath), target->preview_RuntimeContext(), this->viewport);
        this->inputDispatcher.Cancel();
        target->preview_ReplaceRuntimeTree(std::move(tree));
        // Новый runtime-корень тоже подключается к общему контроллеру.
        this->AttachAnimations();
        this->dirty = true;
        error.clear();
        return true;
    }
#endif
    //
    // Internal
    //

    template <typename TTraits>
    std::string_view PageManagerBase<TTraits>::ResolveTarget(const NavigationRoute& navigationRoute) const {
        if (navigationRoute.targetKind == NavigationTargetKind::page) {
            return navigationRoute.target;
        }
        return this->history.size() < 2 ? std::string_view{} : this->history[this->history.size() - 2].page->Name();
    }

    template <typename TTraits>
    bool PageManagerBase<TTraits>::Navigate(const NavigationRoute& navigationRoute, std::unique_ptr<NavigationStateBase> navigationState) {
        auto* target = this->pageRegistry.Find(this->ResolveTarget(navigationRoute));
        if (!this->CanNavigate(navigationRoute) || this->navigating || this->IsTransitioning() || target == nullptr || target == this->currentPage
            || this->currentPage == nullptr || navigationRoute.source != this->CurrentPageName()) {
            return false;
        }
        this->navigating = true;
        struct NavigationGuard final {
            bool& active;
            ~NavigationGuard() { active = false; }
        } guard{this->navigating};
        const NavigationRequest navigationRequest{navigationRoute.source, target->Name(), navigationRoute.trigger};
        auto outgoingState = this->currentPage->OnNavigatingFrom(navigationRequest);
        if (!navigationState) {
            navigationState = std::move(outgoingState);
        }
        if (!this->IsNavigationDataValid(navigationRoute, navigationState.get()) || !target->OnNavigatingTo(navigationRequest, std::move(navigationState))) {
            return false;
        }
        this->inputDispatcher.Cancel();
        this->outgoingPage = this->currentPage;
        this->currentPage = target;
        if (navigationRoute.targetKind == NavigationTargetKind::previousPage) {
            this->history.pop_back();
        } else {
            this->history.push_back({target, &navigationRoute});
        }
        this->outgoingPage->Root().SetVisibility(xaml::attr::Visibility::collapsed);
        this->Root().SetVisibility(xaml::attr::Visibility::visible);
        const std::string direction = navigationRoute.targetKind == NavigationTargetKind::previousPage ? "Backward" : "Forward";
        for (auto* page : {this->outgoingPage, this->currentPage}) {
            xaml::VisualStateManager::GoToState(page->Root(), "NavigationDirection", "Idle", false);
            xaml::VisualStateManager::GoToState(page->Root(), "NavigationDirection", direction);
            xaml::layoutInViewport(page->Root(), this->viewport);
        }
        this->UpdateTransition();
        this->dirty = true;
        return true;
    }

    template <typename TTraits>
    bool PageManagerBase<TTraits>::IsNavigationDataValid(const NavigationRoute& navigationRoute, const NavigationStateBase* navigationState) {
        if (navigationRoute.dataContract == nullptr) {
            return navigationState == nullptr;
        }
        return navigationState == nullptr ? !navigationRoute.dataContract->isRequired : navigationState->TypeId() == navigationRoute.dataContract->typeId;
    }

    template <typename TTraits>
    void PageManagerBase<TTraits>::AttachAnimations() {
        this->animationController = xaml::AnimationController{};
        this->outgoingPage = nullptr;
        this->pageRegistry.ForEach([this](Page& page) {
            // Видимость устанавливаем до Attach, без проигрывания перехода при загрузке.
            page.Root().SetVisibility(&page == this->currentPage
                ? xaml::attr::Visibility::visible : xaml::attr::Visibility::collapsed);
            this->animationController.Attach(page.Root(), xaml::AnimationRegistry{});
        });
        this->animationController.SetPlaybackRate(this->playbackRate);
    }

    template <typename TTraits>
    void PageManagerBase<TTraits>::UpdateTransition() {
        if (this->outgoingPage != nullptr
            && !xaml::AnimationController::IsAnimating(this->outgoingPage->Root())
            && !xaml::AnimationController::IsAnimating(this->Root())) {
            this->outgoingPage = nullptr;
        }
    }
}