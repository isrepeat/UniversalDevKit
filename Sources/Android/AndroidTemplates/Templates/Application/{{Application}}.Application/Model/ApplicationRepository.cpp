#include "ApplicationRepository.h"

#include <utility>

namespace {{application}}::application::model {
    ApplicationRepository::ApplicationRepository(core::ApplicationStateStore& applicationStateStore)
        : base::AppRepositoryBase(applicationStateStore) {
    }
#if defined(ANDROID_APP_PREVIEWER)
    //
    // AppRepositoryBase
    //
    bool ApplicationRepository::preview_IsSessionDocumentEquivalentTo(const ApplicationStateDocument& applicationStateDocument) const {
        return this->base::AppRepositoryBase::State() == applicationStateDocument;
    }

    void ApplicationRepository::preview_ReloadFromStateStore() {
        // Репозиторий читает документ напрямую, отдельного кэша нет.
    }
#endif
    //
    // API
    //
    const std::string& ApplicationRepository::Greeting() const {
        return this->base::AppRepositoryBase::State().greeting;
    }

    bool ApplicationRepository::SetGreeting(std::string value) {
        auto applicationStateDocument = this->base::AppRepositoryBase::State();
        applicationStateDocument.greeting = std::move(value);
        return this->base::AppRepositoryBase::Commit(std::move(applicationStateDocument));
    }
}