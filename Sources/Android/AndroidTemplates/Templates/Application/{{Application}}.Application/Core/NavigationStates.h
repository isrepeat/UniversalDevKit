#pragma once
#include "./Navigation.h"

#include <string>

namespace {{application}}::application::core {
    class GreetingNavigationState final : public NavigationState<GreetingNavigationState> {
    public:
        static constexpr std::string_view DataTypeId = "GreetingNavigationState";
        static constexpr bool IsRequired = true;
#if defined(ANDROID_APP_PREVIEWER)
        static std::unique_ptr<base::NavigationStateBase> preview_CreatePreviewDefault();
#endif
        std::string Message;
    };
}