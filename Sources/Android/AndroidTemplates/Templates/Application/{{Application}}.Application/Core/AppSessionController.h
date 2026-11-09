#pragma once
#include <UniversalDevKit/Android/AndroidBuildTools/ApplicationFramework/AppSessionControllerBase.h>

#include "../Interface/IHostCommandDispatcher.h"

namespace {{application}}::application::core {
    class AppSessionController final : public universaldevkit::android::androidbuildtools::applicationframework::AppSessionControllerBase<
        interface::IHostCommandDispatcher, HostCommand, HostCommandData> {
    protected:
        void OnUnhandledHostCommand(HostCommand hostCommand, const HostCommandData& hostCommandData) override;
    };
}