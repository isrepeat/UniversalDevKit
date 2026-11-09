#pragma once
#include "../Export.h"
#include <AndroidAppPreviewerPluginSdk/Session/PreviewSessionBase.h>

#include <memory>
#include <string>

namespace universaldevkit::windows::androidapppreviewerpluginsdk::session {
    using PreviewSessionFactory = std::unique_ptr<PreviewSessionBase> (*)(int, int);
    using PluginInfoProvider = std::string (*)();

    class UNIVERSALDEVKIT_ANDROIDAPPPREVIEWERPLUGINSDK_API PluginDefinition final {
    public:
        PluginDefinition(PreviewSessionFactory previewSessionFactory, PluginInfoProvider pluginInfoProvider);
        static std::unique_ptr<PreviewSessionBase> CreatePreviewSession(int width, int height);
        static std::string PluginInfoJson();
    };
}