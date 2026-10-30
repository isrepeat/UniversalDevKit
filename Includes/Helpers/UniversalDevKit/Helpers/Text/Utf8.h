#pragma once
#include <string_view>
#include <cstddef>
#include <cstdint>

namespace universaldevkit::helpers::text {
    class Utf8 final {
    public:
        static bool TryNext(const char*& current, const char* end, std::uint32_t& scalar) noexcept {
            if (current == end) { return false; }
            const auto lead = static_cast<unsigned char>(*current++);
            if (lead < 0x80) { scalar = lead; return true; }
            unsigned count;
            std::uint32_t minimum;
            if (lead >= 0xC2 && lead <= 0xDF) { count = 1; minimum = 0x80; scalar = lead & 0x1F; }
            else if (lead >= 0xE0 && lead <= 0xEF) { count = 2; minimum = 0x800; scalar = lead & 0x0F; }
            else if (lead >= 0xF0 && lead <= 0xF4) { count = 3; minimum = 0x10000; scalar = lead & 0x07; }
            else { return false; }
            if (end - current < count) { return false; }
            for (unsigned index = 0; index < count; ++index) {
                const auto next = static_cast<unsigned char>(current[index]);
                if ((next & 0xC0) != 0x80) { return false; }
                scalar = (scalar << 6) | (next & 0x3F);
            }
            current += count;
            return scalar >= minimum && scalar <= 0x10FFFF && !(scalar >= 0xD800 && scalar <= 0xDFFF);
        }

        static std::uint32_t Next(const char*& current, const char* end, std::uint32_t replacement = 0xFFFD) noexcept {
            std::uint32_t scalar;
            return Utf8::TryNext(current, end, scalar) ? scalar : replacement;
        }

        static std::size_t Length(std::string_view text) noexcept {
            const char* current = text.data();
            const char* end = current;
            if (!text.empty()) { end += text.size(); }
            std::size_t length = 0;
            while (current != end) { Utf8::Next(current, end); ++length; }
            return length;
        }
    };
}