#include <AndroidAppPreviewerPluginSdk/Session/PluginDefinition.h>

#include <stdexcept>

namespace universaldevkit::windows::androidapppreviewerpluginsdk::session {
    namespace details {
        struct PluginCallbacks final {
            PreviewSessionFactory previewSessionFactory = nullptr;
            PluginInfoProvider pluginInfoProvider = nullptr;
        };

        PluginCallbacks& GetPluginCallbacks() {
            static PluginCallbacks pluginCallbacks;
            return pluginCallbacks;
        }
    } // namespace details

    PluginDefinition::PluginDefinition(PreviewSessionFactory previewSessionFactory, PluginInfoProvider pluginInfoProvider) {
        if (previewSessionFactory == nullptr || pluginInfoProvider == nullptr) {
            throw std::invalid_argument("Preview plugin callbacks are required");
        }
        details::GetPluginCallbacks() = {previewSessionFactory, pluginInfoProvider};
    }

    std::unique_ptr<PreviewSessionBase> PluginDefinition::CreatePreviewSession(int width, int height) {
        const auto previewSessionFactory = details::GetPluginCallbacks().previewSessionFactory;
        if (previewSessionFactory == nullptr) {
            throw std::logic_error("Preview plugin definition was not registered");
        }
        return previewSessionFactory(width, height);
    }

    std::string PluginDefinition::PluginInfoJson() {
        const auto pluginInfoProvider = details::GetPluginCallbacks().pluginInfoProvider;
        if (pluginInfoProvider == nullptr) {
            throw std::logic_error("Preview plugin definition was not registered");
        }
        return pluginInfoProvider();
    }
}