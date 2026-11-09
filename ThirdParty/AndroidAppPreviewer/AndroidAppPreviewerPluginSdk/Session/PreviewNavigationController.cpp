#include <AndroidAppPreviewerPluginSdk/Session/PreviewNavigationController.h>

#include <AndroidAppPreviewerPluginSdk/Session/PreviewSessionBase.h>

#include <set>

namespace universaldevkit::windows::androidapppreviewerpluginsdk::session {
    namespace details {
        std::string JsonString(std::string_view value) {
            std::string result = "\"";
            constexpr char digits[] = "0123456789abcdef";
            for (const unsigned char c : value) {
                if (c == '"' || c == '\\') {
                    result += '\\';
                    result += c;
                } else if (c < 32) {
                    result += "\\u00";
                    result += digits[c >> 4];
                    result += digits[c & 15];
                } else {
                    result += c;
                }
            }
            return result + '"';
        }
    }

    PreviewNavigationController::PreviewNavigationController(PreviewSessionBase& session)
        : session(session) {
    }

    //
    // Методы
    //
    std::string PreviewNavigationController::BuildGraphJson() const {
        const auto routes = this->session.Routes();
        std::set<std::string_view> pages;
        pages.insert(this->session.CurrentPage());
        for (const auto& route : routes) {
            pages.insert(route.source);
            pages.insert(route.target);
        }
        std::string result = "{\"currentPageId\":" + details::JsonString(this->session.CurrentPage())
            + ",\"layoutRootPageId\":" + details::JsonString(this->session.LayoutRootPage()) + ",\"pages\":[";
        bool first = true;
        for (const auto page : pages) {
            if (!first) {
                result += ',';
            }
            first = false;
            result += "{\"id\":" + details::JsonString(page) + ",\"title\":" + details::JsonString(this->session.PageTitle(page)) + '}';
        }
        result += "],\"transitions\":[";
        first = true;
        for (const auto& route : routes) {
            if (!first) {
                result += ',';
            }
            first = false;
            result += "{\"id\":" + details::JsonString(route.id)
                + ",\"sourcePageId\":" + details::JsonString(route.source)
                + ",\"targetPageId\":" + details::JsonString(route.target)
                + ",\"backwardOfTransitionId\":" + details::JsonString(route.backwardOfRouteId)
                + ",\"title\":" + details::JsonString(route.title)
                + ",\"targetKind\":" + details::JsonString(
                    route.isPreviousPage
                        ? "previousPage"
                        : "page")
                + ",\"isDefault\":" + (route.isDefault ? "true" : "false")
                + ",\"dataType\":" + details::JsonString(route.dataType)
                + ",\"hasPreviewDefaultNavigationState\":" + (route.hasPreviewDefaultNavigationState ? "true" : "null") + '}';
        }
        return result + "]}";
    }

    bool PreviewNavigationController::Navigate(std::span<const std::string_view> transitionIds, std::string& error) {
        return this->session.Navigate(transitionIds, error);
    }
}