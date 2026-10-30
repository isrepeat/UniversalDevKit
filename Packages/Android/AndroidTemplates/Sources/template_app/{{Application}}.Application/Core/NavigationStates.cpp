#include "NavigationStates.h"

namespace {{application}}::application::core {
#if defined(ANDROID_APP_PREVIEWER)
    //
    // API
    //
    std::unique_ptr<base::NavigationStateBase> GreetingNavigationState::preview_CreatePreviewDefault() {
        auto greetingNavigationState = std::make_unique<GreetingNavigationState>();
        greetingNavigationState->Message = "Hello from preview!";
        return greetingNavigationState;
    }
#endif
}