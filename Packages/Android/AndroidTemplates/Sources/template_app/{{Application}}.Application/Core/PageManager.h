#pragma once
#include <AndroidBuildTools/ApplicationFramework/PageManagerBase.h>

#include "../UI/Page/SettingsPageViewModel.h"
#include "../UI/Page/MainPageViewModel.h"
#include "./PageRegistry.h"
#include "./Navigation.h"

namespace {{application}}::application::core {
    struct PageManagerTraits final {
        using Page = interface::IPage;
        using PageNavigator = interface::IPageNavigator;
        using NavigationStateBase = base::NavigationStateBase;
        using NavigationTrigger = core::NavigationTrigger;
        using NavigationTargetKind = core::NavigationTargetKind;
        using NavigationRequest = core::NavigationRequest;
        using NavigationDataContract = core::NavigationDataContract;
        using PageContext = core::PageContext;
        using ApplicationRepository = model::ApplicationRepository;
        using AppSessionController = core::AppSessionController;
        using PageRegistry = core::PageRegistry<ui::page::MainPageViewModel, ui::page::SettingsPageViewModel>;

        static std::string_view InitialPageName();
    };

    class PageManager final : public application_framework::PageManagerBase<PageManagerTraits> {
    public:
        PageManager(model::ApplicationRepository& applicationRepository, AppSessionController& appSessionController);

    protected:
        //
        // PageManagerBase
        //
        std::span<const NavigationRoute> Routes() const override;
    };
}