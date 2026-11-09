#include "PageManager.h"

#include "./NavigationStates.h"

#include <array>

namespace {{application}}::application::core {
    std::string_view PageManagerTraits::InitialPageName() {
        return ui::page::MainPageViewModel::PageName;
    }

    PageManager::PageManager(model::ApplicationRepository& applicationRepository, AppSessionController& appSessionController)
        : PageManagerBase(applicationRepository, appSessionController) {
    }

    //
    // PageManagerBase
    //
    std::span<const PageManager::NavigationRoute> PageManager::Routes() const {
        static const std::array routes{
            NavigationRoute{
                "main-to-settings", "MainPage", NavigationTrigger::navigateToSettings, "SettingsPage",
                NavigationTargetKind::page, &GreetingNavigationState::Contract(), "Open settings"
            },
            NavigationRoute{
                "settings-to-main", "SettingsPage", NavigationTrigger::navigateBack, {},
                NavigationTargetKind::previousPage, nullptr, "Back"
            },
        };
        return routes;
    }
}