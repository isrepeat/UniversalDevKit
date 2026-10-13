#include <UniversalDevKit/Helpers/Text.h>

namespace universaldevkit::text {
    bool EndsWithLineBreak(std::string_view text) noexcept {
        return !text.empty() && (text.back() == '\n' || text.back() == '\r');
    }
}