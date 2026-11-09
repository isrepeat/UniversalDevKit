#include "Internal/Bridge/TextBuffer.h"

#include <stdexcept>
#include <cstring>

namespace universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge {
    //
    // Методы
    //
    void TextBuffer::Write(
        std::string_view source,
        char* destination,
        size_t capacity,
        const char* tooSmallMessage) {
        if (source.size() >= capacity) {
            throw std::invalid_argument(tooSmallMessage);
        }
        std::memcpy(destination, source.data(), source.size());
        destination[source.size()] = '\0';
    }
}