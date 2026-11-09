#include "Internal/Abi/PreviewPluginAbi.h"

#include <AndroidAppPreviewerPluginSdk/Session/PluginDefinition.h>

#include "Internal/Bridge/Diagnostic.h"
#include "Internal/Bridge/TextBuffer.h"

#include <stdexcept>

namespace universaldevkit::windows::androidapppreviewerpluginsdk::internal::abi {
    const char* PreviewPluginAbi::LastError() {
        return bridge::LastError().c_str();
    }

    uint32_t PreviewPluginAbi::AbiVersion() {
        return universaldevkit::windows::androidapppreviewerpluginsdk::android_app_previewer_plugin_abi_version;
    }

    bool PreviewPluginAbi::WritePluginInfo(char* destination, int capacity) {
        if (destination == nullptr || capacity <= 0) {
            throw std::invalid_argument("Plugin-info buffer and positive capacity are required");
        }
        bridge::TextBuffer::Write(
            session::PluginDefinition::PluginInfoJson(),
            destination,
            static_cast<size_t>(capacity),
            "Plugin-info buffer is too small"
        );
        return true;
    }

    universaldevkit::windows::androidapppreviewerpluginsdk::xp_session* PreviewPluginAbi::CreateSession(int width, int height) {
        return new universaldevkit::windows::androidapppreviewerpluginsdk::xp_session(width, height);
    }

    void PreviewPluginAbi::DestroySession(universaldevkit::windows::androidapppreviewerpluginsdk::xp_session* session) {
        delete session;
    }
}