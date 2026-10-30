#pragma once
#include "Utf8.h"

#include <string_view>
#include <stdexcept>
#include <cstdint>
#include <string>

namespace universaldevkit::helpers::text {
    class Unicode final {
    public:
        Unicode() = delete;

        // wchar_t carries UTF-16 on Windows and Unicode scalars on UTF-32 platforms.
        static std::string ToUtf8(std::wstring_view text) {
            static_assert(sizeof(wchar_t) == 2 || sizeof(wchar_t) == 4);
            std::string result;
            for (std::size_t index = 0; index < text.size(); ++index) {
                auto scalar = static_cast<std::uint32_t>(text[index]);
                if constexpr (sizeof(wchar_t) == 2) {
                    if (scalar >= 0xD800 && scalar <= 0xDBFF) {
                        if (++index == text.size()) {
                            throw std::invalid_argument("Incomplete UTF-16 surrogate pair");
                        }
                        const auto low = static_cast<std::uint32_t>(text[index]);
                        if (low < 0xDC00 || low > 0xDFFF) {
                            throw std::invalid_argument("Invalid UTF-16 surrogate pair");
                        }
                        scalar = 0x10000 + ((scalar - 0xD800) << 10) + low - 0xDC00;
                    }
                }
                if (scalar > 0x10FFFF || (scalar >= 0xD800 && scalar <= 0xDFFF)) {
                    throw std::invalid_argument("Invalid Unicode scalar");
                }
                if (scalar < 0x80) {
                    result.push_back(static_cast<char>(scalar));
                }
                else if (scalar < 0x800) {
                    result.push_back(static_cast<char>(0xC0 | (scalar >> 6)));
                    result.push_back(static_cast<char>(0x80 | (scalar & 0x3F)));
                }
                else if (scalar < 0x10000) {
                    result.push_back(static_cast<char>(0xE0 | (scalar >> 12)));
                    result.push_back(static_cast<char>(0x80 | ((scalar >> 6) & 0x3F)));
                    result.push_back(static_cast<char>(0x80 | (scalar & 0x3F)));
                }
                else {
                    result.push_back(static_cast<char>(0xF0 | (scalar >> 18)));
                    result.push_back(static_cast<char>(0x80 | ((scalar >> 12) & 0x3F)));
                    result.push_back(static_cast<char>(0x80 | ((scalar >> 6) & 0x3F)));
                    result.push_back(static_cast<char>(0x80 | (scalar & 0x3F)));
                }
            }
            return result;
        }

        static std::wstring FromUtf8(std::string_view text) {
            static_assert(sizeof(wchar_t) == 2 || sizeof(wchar_t) == 4);
            std::wstring result;
            const char* current = text.data();
            const char* end = current;
            if (!text.empty()) { end += text.size(); }
            while (current != end) {
                std::uint32_t scalar;
                if (!Utf8::TryNext(current, end, scalar)) {
                    throw std::invalid_argument("Invalid UTF-8 sequence" );
                }
                if constexpr (sizeof(wchar_t) == 2) {
                    if (scalar > 0xFFFF) {
                        scalar -= 0x10000;
                        result.push_back(static_cast<wchar_t>(0xD800 + (scalar >> 10)));
                        result.push_back(static_cast<wchar_t>(0xDC00 + (scalar & 0x3FF)));
                        continue;
                    }
                }
                result.push_back(static_cast<wchar_t>(scalar));
            }
            return result;
        }
    };
}