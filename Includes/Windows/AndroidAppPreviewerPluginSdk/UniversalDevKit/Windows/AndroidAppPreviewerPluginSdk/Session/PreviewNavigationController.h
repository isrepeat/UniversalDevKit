#pragma once
#include <string_view>
#include <string>
#include <span>

namespace universaldevkit::windows::androidapppreviewerpluginsdk::session {
    class PreviewSessionBase;

    class PreviewNavigationController final {
    public:
        explicit PreviewNavigationController(PreviewSessionBase& session);

        std::string BuildGraphJson() const;
        bool Navigate(std::span<const std::string_view> transitionIds, std::string& error);

    private:
        PreviewSessionBase& session;
    };
}