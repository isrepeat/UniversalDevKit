#pragma once
#include "Config.h"

#include <string_view>
#include <type_traits>
#include <filesystem>
#include <format>

#if !defined(__cpp_lib_format_path) // C++23 feature-test: built-in formatter for std::filesystem::path
//
// ░ std::filesystem::path
// ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
//
template <class CharT>
struct std::formatter<std::filesystem::path, CharT> {
    constexpr auto parse(std::basic_format_parse_context<CharT>& ctx) {
        return this->innerFormatter.parse(ctx); // Delegate parsing of format specifiers ({:>10.3}, etc.).
    }

    template <class FormatContext>
    auto format(const std::filesystem::path& path, FormatContext& ctx) const {
        if constexpr (std::is_same_v<CharT, wchar_t>) {
            const auto& s = path.native(); // Wide characters on Windows.
            return this->innerFormatter.format(std::basic_string_view<wchar_t>{s.data(), s.size()}, ctx);
        }
        else {
            // Narrow output uses UTF-8:
            // .string() on Windows depends on the system ANSI code page,
            // so use .u8string() and interpret its UTF-8 bytes as char.
            const auto u8 = path.u8string(); // std::u8string (UTF-8)
            const auto sv = std::string_view{reinterpret_cast<const char*>(u8.data()), u8.size()};
            return this->innerFormatter.format(sv, ctx);
        }
    }

private:
    std::formatter<std::basic_string_view<CharT>, CharT> innerFormatter;
};
#endif