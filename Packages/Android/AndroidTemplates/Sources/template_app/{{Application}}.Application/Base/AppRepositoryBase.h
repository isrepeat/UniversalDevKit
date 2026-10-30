#pragma once
#include "../Core/ApplicationStateStore.h"

#include <string>

namespace {{application}}::application::model {
    struct ApplicationStateDocument;
}

namespace {{application}}::application::base {
    class AppRepositoryBase {
    public:
        virtual ~AppRepositoryBase() = default;

#if defined(ANDROID_APP_PREVIEWER)
        void preview_LoadScenarioState(model::ApplicationStateDocument applicationStateDocument);
        bool preview_SaveStateToPersistentStorage();
        virtual bool preview_IsSessionDocumentEquivalentTo(const model::ApplicationStateDocument& applicationStateDocument) const = 0;
        virtual void preview_ReloadFromStateStore() = 0;
#endif

    protected:
        explicit AppRepositoryBase(core::ApplicationStateStore& applicationStateStore);

        const model::ApplicationStateDocument& State() const;
        bool Commit(model::ApplicationStateDocument applicationStateDocument);

    private:
        core::ApplicationStateStore& applicationStateStore;
    };
}