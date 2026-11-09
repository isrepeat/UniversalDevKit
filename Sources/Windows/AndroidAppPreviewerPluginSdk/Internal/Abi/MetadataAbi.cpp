#include "Internal/Abi/MetadataAbi.h"

#include "Internal/Bridge/PreviewPluginSdkTypes.h"
#include "Internal/Bridge/Diagnostic.h"
#include "Internal/Bridge/TextBuffer.h"
#include "Internal/Abi/PreviewPluginAbi.h"
#include "Internal/Abi/SessionAbi.h"

#include <string_view>
#include <stdexcept>
#include <string>
#include <vector>

namespace universaldevkit::windows::androidapppreviewerpluginsdk::internal::abi {
    using namespace universaldevkit::windows::androidapppreviewerpluginsdk;

    //
    // Методы
    //
    const char* MetadataAbi::xp_last_error(void) {
        return universaldevkit::windows::androidapppreviewerpluginsdk::internal::abi::PreviewPluginAbi::LastError();
    }

    uint32_t MetadataAbi::xp_get_abi_version(void) {
        return universaldevkit::windows::androidapppreviewerpluginsdk::internal::abi::PreviewPluginAbi::AbiVersion();
    }

    int MetadataAbi::xp_get_plugin_info(
        char* pluginInfoJson,
        int capacity
    ) {
        try {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError().clear();
            return universaldevkit::windows::androidapppreviewerpluginsdk::internal::abi::PreviewPluginAbi::WritePluginInfo(pluginInfoJson, capacity) ? 1 : 0;
        } catch (const std::exception& error) {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError() = error.what();
            return 0;
        }
    }

    int MetadataAbi::xp_get_initial_page_id(
        void* session,
        char* pageId,
        int capacity
    ) {
        return universaldevkit::windows::androidapppreviewerpluginsdk::internal::abi::SessionAbi::xp_session_current_page(static_cast<xp_session*>(session), pageId, capacity);
    }

    int MetadataAbi::xp_get_navigation_graph(
        void* session,
        char* graphJson,
        int capacity
    ) {
        try {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError().clear();
            if (session == nullptr || graphJson == nullptr || capacity <= 0) {
                throw std::invalid_argument("Session, graph buffer and positive capacity are required");
            }
            const std::string json = static_cast<xp_session*>(session)->value.Navigation().BuildGraphJson();
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::TextBuffer::Write(
                json,
                graphJson,
                static_cast<size_t>(capacity),
                "Navigation graph buffer is too small");
            return 1;
        } catch (const std::exception& error) {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError() = error.what();
            return 0;
        }
    }

    int MetadataAbi::xp_navigate(
        void* session,
        const char* navigationRequestJson
    ) {
        try {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError().clear();
            if (session == nullptr || navigationRequestJson == nullptr) {
                throw std::invalid_argument("Session and navigation request are required");
            }
            const std::vector<std::string> ids = universaldevkit::windows::androidapppreviewerpluginsdk::session::PreviewSessionBase::ParseNavigationTransitionIds(navigationRequestJson);
            std::vector<std::string_view> transitionIds;
            transitionIds.reserve(ids.size());
            for (const std::string& id : ids) {
                transitionIds.push_back(id);
            }
            if (!static_cast<xp_session*>(session)->value.Navigation().Navigate(
                transitionIds,
                universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError())) {
                return 0;
            }
            return 1;
        } catch (const std::exception& error) {
            universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge::LastError() = error.what();
            return 0;
        }
    }
} // namespace universaldevkit::windows::androidapppreviewerpluginsdk::internal::abi