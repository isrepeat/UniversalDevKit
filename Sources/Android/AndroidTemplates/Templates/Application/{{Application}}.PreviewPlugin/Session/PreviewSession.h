#pragma once
#include <UniversalDevKit/Windows/AndroidAppPreviewerPluginSdk/Session/ApplicationPreviewSession.h>

#include "../../{{Application}}.Application/Core/ApplicationSession.h"

namespace {{application}}::preview::session {
    class PreviewSession final : public universaldevkit::windows::androidapppreviewerpluginsdk::session::ApplicationPreviewSession<application::core::ApplicationSession> {
    public:
        PreviewSession(int width, int height);
    };
}