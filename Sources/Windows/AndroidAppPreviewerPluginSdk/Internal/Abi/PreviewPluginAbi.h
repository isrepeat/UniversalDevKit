#pragma once
#include "Internal/Bridge/PreviewPluginSdkTypes.h"

#include <cstdint>

namespace universaldevkit::windows::androidapppreviewerpluginsdk::internal::abi {
    //
    // Фасад сведений о плагине и жизненного цикла C ABI session handle.
    //
    class PreviewPluginAbi final {
    public:
        static const char* LastError();
        static uint32_t AbiVersion();
        static bool WritePluginInfo(char* destination, int capacity);
        static universaldevkit::windows::androidapppreviewerpluginsdk::xp_session* CreateSession(int width, int height);
        static void DestroySession(universaldevkit::windows::androidapppreviewerpluginsdk::xp_session* session);
    };
}