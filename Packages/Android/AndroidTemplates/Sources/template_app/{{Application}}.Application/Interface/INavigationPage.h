#pragma once
#include "../Base/NavigationStateBase.h"

#include <memory>

namespace {{application}}::application::core {
    struct NavigationRequest;
}

namespace {{application}}::application::interface {
    class INavigationPage {
    public:
        virtual ~INavigationPage() = default;
        virtual std::unique_ptr<base::NavigationStateBase> OnNavigatingFrom(const core::NavigationRequest& navigationRequest) = 0;
        virtual bool OnNavigatingTo(const core::NavigationRequest& navigationRequest, std::unique_ptr<base::NavigationStateBase> navigationState) = 0;
    };
}