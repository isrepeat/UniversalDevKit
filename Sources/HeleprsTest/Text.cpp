#include <UniversalDevKit/HeleprsTest/Text.h>

namespace universaldevkit::heleprstest::text {
    bool EndsWithLineBreak(std::string_view text) noexcept {
        return !text.empty() && (text.back() == '\n' || text.back() == '\r');
    }
}