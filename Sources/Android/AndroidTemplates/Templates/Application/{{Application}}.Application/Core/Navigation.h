#pragma once
#include "../Interface/INavigationPage.h"
#include "../Interface/IPageNavigator.h"
#include "../Base/NavigationStateBase.h"

#include <string_view>
#include <memory>

namespace {{application}}::application::core {
    // Defines data accepted on a particular graph edge. The native type creates
    // the preview default so the previewer never constructs domain objects.
    struct NavigationDataContract final {
        std::string_view typeId;
#if defined(ANDROID_APP_PREVIEWER)
        std::unique_ptr<base::NavigationStateBase> (*preview_CreatePreviewDefaultFn)();
#endif
        bool isRequired;
    };

    // Shared navigation payload contract. A concrete type specifies its ID,
    // whether it is required, and how to construct preview state.
    template <typename TDerived>
    class NavigationState : public base::NavigationStateBase {
    public:
        static const NavigationDataContract& Contract() {
            static const NavigationDataContract contract{
                TDerived::DataTypeId,
#if defined(ANDROID_APP_PREVIEWER)
                &TDerived::preview_CreatePreviewDefault,
#endif
                TDerived::IsRequired,
            };
            return contract;
        }

        std::string_view TypeId() const final {
            return this->Contract().typeId;
        }
    };

    // Marker for transitions that accept no payload.
    struct NoNavigationData final {};

    enum class NavigationTrigger {
        navigateToSettings,
        navigateBack,
    };

    enum class NavigationTargetKind {
        page,
        // The previous entry in the actual PageManager history determines the destination.
        previousPage,
    };

    struct NavigationRequest final {
        std::string_view source;
        std::string_view target;
        NavigationTrigger navigationTrigger;
    };
}