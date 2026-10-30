#pragma once
#include "Config.h"

#include <string_view>
#include <type_traits>
#include <filesystem>
#include <cstdint>
#include <utility>
#include <format>
#include <string>

namespace universaldevkit::helpers::stdext {
    //
    // ░ Path formatting
    // ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
    //
    // Own the path so storing the wrapper never borrows a temporary path.
    class FormattedPath {
    public:
        explicit FormattedPath(std::filesystem::path path)
            : path{std::move(path)} {
        }

        std::u8string Utf8() const {
            return this->path.u8string();
        }

        std::wstring Wide() const {
            // Decode UTF-8 explicitly: POSIX path::wstring may depend on the locale.
            const auto text = this->Utf8();
            std::wstring result;
            result.reserve(text.size());
            for (std::size_t index = 0; index < text.size();) {
                auto codePoint = static_cast<std::uint32_t>(text[index++]);
                unsigned continuationCount = 0;
                std::uint32_t minimum = 0;
                if (codePoint < 0x80) {
                    // ASCII needs no continuation bytes.
                }
                else if (codePoint >= 0xC2 && codePoint <= 0xDF) {
                    codePoint &= 0x1F;
                    continuationCount = 1;
                    minimum = 0x80;
                }
                else if (codePoint >= 0xE0 && codePoint <= 0xEF) {
                    codePoint &= 0x0F;
                    continuationCount = 2;
                    minimum = 0x800;
                }
                else if (codePoint >= 0xF0 && codePoint <= 0xF4) {
                    codePoint &= 0x07;
                    continuationCount = 3;
                    minimum = 0x10000;
                }
                else {
                    throw std::format_error("Path is not valid UTF-8");
                }

                for (unsigned count = 0; count < continuationCount; ++count) {
                    if (index == text.size()) {
                        throw std::format_error("Truncated UTF-8 path");
                    }
                    const auto next = static_cast<std::uint32_t>(text[index++]);
                    if ((next & 0xC0) != 0x80) {
                        throw std::format_error("Invalid UTF-8 continuation byte");
                    }
                    codePoint = (codePoint << 6) | (next & 0x3F);
                }
                if (codePoint < minimum || codePoint > 0x10FFFF || (codePoint >= 0xD800 && codePoint <= 0xDFFF)) {
                    throw std::format_error("Invalid Unicode scalar in path");
                }

                if constexpr (sizeof(wchar_t) == 2) {
                    if (codePoint > 0xFFFF) {
                        codePoint -= 0x10000;
                        result.push_back(static_cast<wchar_t>(0xD800 + (codePoint >> 10)));
                        result.push_back(static_cast<wchar_t>(0xDC00 + (codePoint & 0x3FF)));
                        continue;
                    }
                }
                result.push_back(static_cast<wchar_t>(codePoint));
            }
            return result;
        }

    private:
        std::filesystem::path path;
    };

    inline FormattedPath Path(std::filesystem::path path) {
        return FormattedPath{std::move(path)};
    }
}

//
// ░ Formatter for the program-defined wrapper
// ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
//
template <class CharT>
struct std::formatter<universaldevkit::helpers::stdext::FormattedPath, CharT> {
    constexpr auto parse(std::basic_format_parse_context<CharT>& ctx) {
        return this->innerFormatter.parse(ctx);
    }

    template <class FormatContext>
    auto format(const universaldevkit::helpers::stdext::FormattedPath& formattedPath, FormatContext& ctx) const {
        if constexpr (std::is_same_v<CharT, wchar_t>) {
            const auto text = formattedPath.Wide();
            return this->innerFormatter.format(std::wstring_view{text}, ctx);
        }
        else {
            const auto text = formattedPath.Utf8();
            const auto view = std::string_view{reinterpret_cast<const char*>(text.data()), text.size()};
            return this->innerFormatter.format(view, ctx);
        }
    }

private:
    std::formatter<std::basic_string_view<CharT>, CharT> innerFormatter;
};