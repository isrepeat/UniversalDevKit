#include "AppRepositoryBase.h"

#include <utility>

namespace {{application}}::application::base {
    AppRepositoryBase::AppRepositoryBase(core::ApplicationStateStore& applicationStateStore)
        : applicationStateStore(applicationStateStore) {
    }

    const model::ApplicationStateDocument& AppRepositoryBase::State() const {
        return this->applicationStateStore.CurrentDocument();
    }

    bool AppRepositoryBase::Commit(model::ApplicationStateDocument applicationStateDocument) {
        return this->applicationStateStore.TrySaveDocument(std::move(applicationStateDocument));
    }

#if defined(ANDROID_APP_PREVIEWER)
    void AppRepositoryBase::preview_LoadScenarioState(model::ApplicationStateDocument applicationStateDocument) {
        this->applicationStateStore.preview_LoadSessionDocument(std::move(applicationStateDocument));
        this->preview_ReloadFromStateStore();
    }

    bool AppRepositoryBase::preview_SaveStateToPersistentStorage() {
        return this->applicationStateStore.preview_SaveSessionDocumentToPersistentStorage();
    }
#endif
}