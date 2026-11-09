#pragma once
#include <string_view>
#include <cstddef>

namespace universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge {
    //
    // Записывает строку в буфер C ABI с обязательным нулевым терминатором.
    //
    class TextBuffer final {
    public:
        static void Write(
            std::string_view source,
            char* destination,
            size_t capacity,
            const char* tooSmallMessage);
    };
}