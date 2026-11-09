#pragma once
#include <AndroidAppPreviewerPluginSdk/AndroidAppPreviewerPlugin.h>

namespace universaldevkit::windows::androidapppreviewerpluginsdk::internal::abi {
    using namespace universaldevkit::windows::androidapppreviewerpluginsdk;

    class DiagnosticAbi final {
    public:
        static void xp_configure_logging(const char* filePath);
        static void xp_log_info(const char* message);
    };
}