#pragma once
#include "../Base/AppRepositoryBase.h"

namespace {{application}}::application::model {
    class ApplicationRepository final : public base::AppRepositoryBase {
    public:
        explicit ApplicationRepository(core::ApplicationStateStore& applicationStateStore);
#if defined(ANDROID_APP_PREVIEWER)
        //
        // AppRepositoryBase
        //
        bool preview_IsSessionDocumentEquivalentTo(const ApplicationStateDocument& applicationStateDocument) const override;
        void preview_ReloadFromStateStore() override;
#endif
        const std::string& Greeting() const;
        bool SetGreeting(std::string value);
    };
}