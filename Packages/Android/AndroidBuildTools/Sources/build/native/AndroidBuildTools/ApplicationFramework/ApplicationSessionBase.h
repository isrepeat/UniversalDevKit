#pragma once
#include <UniversalDevKit/XamlRuntime/RenderEngine.h>

#include <utility>

namespace application_framework {
    template <typename TTraits>
    class ApplicationSessionBase {
    public:
        using ApplicationStateDocument = typename TTraits::ApplicationStateDocument;
        using ApplicationStateStore = typename TTraits::ApplicationStateStore;
        using ApplicationRepository = typename TTraits::ApplicationRepository;
        using AppSessionController = typename TTraits::AppSessionController;
        using PageManager = typename TTraits::PageManager;
        explicit ApplicationSessionBase(
            ApplicationStateDocument applicationStateDocument = {},
            typename ApplicationStateStore::DocumentSaveHandler documentSaveHandler = {}
        );
        virtual ~ApplicationSessionBase() = default;
        ApplicationSessionBase(const ApplicationSessionBase&) = delete;
        ApplicationSessionBase& operator=(const ApplicationSessionBase&) = delete;
        AppSessionController& Controller();
        void Initialize(xaml::Size size);
        void Resize(xaml::Size size);
        PageManager& Pages();
        const PageManager& Pages() const;
        ApplicationRepository& Repository();
        xaml::Element& Root();
        void PointerDown(float x, float y);
        void PointerMove(float x, float y);
        void PointerUp(float x, float y);
        void CancelPointer();
        virtual bool Update();
        virtual void Render(xaml::IRenderBackend& renderBackendImpl);

    private:
        ApplicationStateStore applicationStateStore;
        ApplicationRepository applicationRepository;
        AppSessionController appSessionController;
        PageManager pageManager;
        xaml::RendererRegistry rendererRegistry;
    };
}

namespace application_framework {
    template <typename TTraits>
    ApplicationSessionBase<TTraits>::ApplicationSessionBase(
        ApplicationStateDocument applicationStateDocument,
        typename ApplicationStateStore::DocumentSaveHandler documentSaveHandler)
        : applicationStateStore(std::move(applicationStateDocument), std::move(documentSaveHandler))
        , applicationRepository(this->applicationStateStore)
        , pageManager(this->applicationRepository, this->appSessionController) {
    }

    //
    // API
    //
    template <typename TTraits>
    typename TTraits::AppSessionController& ApplicationSessionBase<TTraits>::Controller() {
        return this->appSessionController;
    }

    template <typename TTraits>
    void ApplicationSessionBase<TTraits>::Initialize(xaml::Size size) {
        this->pageManager.Initialize(size);
    }

    template <typename TTraits>
    void ApplicationSessionBase<TTraits>::Resize(xaml::Size size) {
        this->pageManager.Resize(size);
    }

    template <typename TTraits>
    typename TTraits::PageManager& ApplicationSessionBase<TTraits>::Pages() {
        return this->pageManager;
    }

    template <typename TTraits>
    const typename TTraits::PageManager& ApplicationSessionBase<TTraits>::Pages() const {
        return this->pageManager;
    }

    template <typename TTraits>
    typename TTraits::ApplicationRepository& ApplicationSessionBase<TTraits>::Repository() {
        return this->applicationRepository;
    }

    template <typename TTraits>
    xaml::Element& ApplicationSessionBase<TTraits>::Root() {
        return this->pageManager.Root();
    }

    template <typename TTraits>
    void ApplicationSessionBase<TTraits>::PointerDown(float x, float y) {
        this->pageManager.PointerDown(x, y);
    }

    template <typename TTraits>
    void ApplicationSessionBase<TTraits>::PointerMove(float x, float y) {
        this->pageManager.PointerMove(x, y);
    }

    template <typename TTraits>
    void ApplicationSessionBase<TTraits>::PointerUp(float x, float y) {
        this->pageManager.PointerUp(x, y);
    }

    template <typename TTraits>
    void ApplicationSessionBase<TTraits>::CancelPointer() {
        this->pageManager.CancelPointer();
    }

    template <typename TTraits>
    bool ApplicationSessionBase<TTraits>::Update() {
        return this->pageManager.Update();
    }

    template <typename TTraits>
    void ApplicationSessionBase<TTraits>::Render(xaml::IRenderBackend& renderBackendImpl) {
        this->pageManager.Render(renderBackendImpl, this->rendererRegistry);
    }
}