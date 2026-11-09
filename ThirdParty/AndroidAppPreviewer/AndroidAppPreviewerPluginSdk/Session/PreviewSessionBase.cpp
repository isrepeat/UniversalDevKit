#include <AndroidAppPreviewerPluginSdk/Session/PreviewSessionBase.h>

#include <stdexcept>
#include <cctype>

namespace universaldevkit::windows::androidapppreviewerpluginsdk::session {
    PreviewSessionBase::PreviewSessionBase()
        : previewNavigationController(*this) {
    }

    PreviewSessionBase::~PreviewSessionBase() = default;

    PreviewNavigationController& PreviewSessionBase::Navigation() {
        return this->previewNavigationController;
    }

    bool PreviewSessionBase::ApplyScenario(std::string_view, std::string_view) {
        throw std::invalid_argument("This application does not support preview scenarios");
    }

    std::vector<std::string> PreviewSessionBase::ParseNavigationTransitionIds(std::string_view json) {
        const size_t property = json.find("\"transitionIds\"");
        if (property == std::string_view::npos) {
            throw std::invalid_argument("Navigation request does not contain transitionIds");
        }
        const size_t arrayStart = json.find('[', property);
        const size_t arrayEnd = arrayStart == std::string_view::npos ? std::string_view::npos : json.find(']', arrayStart);
        if (arrayStart == std::string_view::npos || arrayEnd == std::string_view::npos) {
            throw std::invalid_argument("Navigation request contains an invalid transitionIds array");
        }
        std::vector<std::string> result;
        size_t position = arrayStart + 1;
        while (position < arrayEnd) {
            while (position < arrayEnd && std::isspace(static_cast<unsigned char>(json[position]))) {
                ++position;
            }
            if (position == arrayEnd) {
                break;
            }
            if (json[position] != '\"') {
                throw std::invalid_argument("Navigation transition ID must be a JSON string");
            }
            const size_t valueStart = ++position;
            const size_t valueEnd = json.find('\"', valueStart);
            if (valueEnd == std::string_view::npos || valueEnd > arrayEnd) {
                throw std::invalid_argument("Navigation transition ID is not terminated");
            }
            if (json.substr(valueStart, valueEnd - valueStart).find('\\') != std::string_view::npos) {
                throw std::invalid_argument("Navigation transition ID must not contain JSON escapes");
            }
            result.emplace_back(json.substr(valueStart, valueEnd - valueStart));
            position = valueEnd + 1;
            while (position < arrayEnd && std::isspace(static_cast<unsigned char>(json[position]))) {
                ++position;
            }
            if (position < arrayEnd) {
                if (json[position] != ',') {
                    throw std::invalid_argument("Navigation transition IDs must be comma-separated");
                }
                ++position;
            }
        }
        if (result.empty()) {
            throw std::invalid_argument("Navigation request does not contain transition IDs");
        }
        return result;
    }
}