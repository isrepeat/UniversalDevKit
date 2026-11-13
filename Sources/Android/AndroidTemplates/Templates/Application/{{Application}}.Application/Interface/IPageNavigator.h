#pragma once
#include <string_view>
#include <memory>

namespace {{application}}::application::core {
    enum class NavigationTrigger;
}

namespace {{application}}::application::base {
    class NavigationStateBase;
}

namespace {{application}}::application::interface {
    class IPageNavigator {
    public:
        virtual ~IPageNavigator() = default;

        virtual bool Navigate(std::string_view pageName) = 0;
        virtual bool Trigger(core::NavigationTrigger navigationTrigger) = 0;
        virtual bool Trigger(
            core::NavigationTrigger navigationTrigger,
            std::unique_ptr<base::NavigationStateBase> navigationState) = 0;
        // The result parameter carries a value independently of returning. A picker can
        // send a selection to the previous page, while Back returns without a value.
        virtual bool NavigateBack(std::unique_ptr<base::NavigationStateBase> navigationState = {}) = 0;

        template <typename TPage>
        bool Navigate() {
            return this->Navigate(TPage::PageName);
        }
    };
}