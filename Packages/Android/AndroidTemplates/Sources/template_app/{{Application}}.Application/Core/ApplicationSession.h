#pragma once
#include <AndroidBuildTools/ApplicationFramework/ApplicationSessionBase.h>

#include "./ApplicationStateStore.h"
#include "./AppSessionController.h"
#include "./PageManager.h"

namespace {{application}}::application::core {
    struct ApplicationSessionTraits final {
        using ApplicationStateDocument = model::ApplicationStateDocument;
        using ApplicationStateStore = core::ApplicationStateStore;
        using ApplicationRepository = model::ApplicationRepository;
        using AppSessionController = core::AppSessionController;
        using PageManager = core::PageManager;
    };

    class ApplicationSession final : public application_framework::ApplicationSessionBase<ApplicationSessionTraits> {
    public:
        explicit ApplicationSession(
            model::ApplicationStateDocument applicationStateDocument = {},
            ApplicationStateStore::DocumentSaveHandler documentSaveHandler = {}
        );
    };
}