#pragma once
#include <UniversalDevKit/Windows/AndroidAppPreviewerPluginSdk/Session/PreviewSessionBase.h>

#include <memory>
#include <string>

namespace universaldevkit::windows::androidapppreviewerpluginsdk {
    // Реализуются приложением; общий runtime не зависит от его конкретных классов.
    std::unique_ptr<session::PreviewSessionBase> CreatePreviewSession(int width, int height);
    std::string PluginInfoJson();
}