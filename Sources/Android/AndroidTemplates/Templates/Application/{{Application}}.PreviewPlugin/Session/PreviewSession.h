#pragma once
#include <AndroidAppPreviewer.PluginSDK/Session/ApplicationPreviewSession.h>

#include "../../{{Application}}.Application/Core/ApplicationSession.h"

namespace {{application}}::preview::session {
    class PreviewSession final : public preview_sdk::session::ApplicationPreviewSession<application::core::ApplicationSession> {
    public:
        PreviewSession(int width, int height);
    };
}