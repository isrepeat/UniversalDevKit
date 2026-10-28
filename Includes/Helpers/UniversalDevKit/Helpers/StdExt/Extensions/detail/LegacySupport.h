#pragma once
#if defined(_WIN32) && defined(_DEBUG)
#pragma push_macro("NOMINMAX")
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <Windows.h>
#pragma pop_macro("NOMINMAX")
#endif

#include <string_view>
#include <type_traits>
#include <exception>
#include <fstream>
#include <format>
#include <string>
#include <vector>
#include <regex>

// Only the dependencies required by fstreamEx are imported here.
namespace universaldevkit::helpers::stdext::extensions::detail::regex {
    namespace details {
        template <typename CharT>
        using view_t = std::basic_string_view<CharT>;

        template <typename CharT>
        using string_t = std::basic_string<CharT, std::char_traits<CharT>, std::allocator<CharT>>;

        template <typename CharT>
        using regex_t = std::basic_regex<CharT>;

        template <typename CharT>
        using iter_t = typename view_t<CharT>::const_iterator;

        template <typename CharT>
        using match_t = std::match_results<iter_t<CharT>>;

        template <typename OutString, typename View, typename It>
        inline OutString ToOutString(View base, const std::sub_match<It>& subMatch) {
            using CharT = typename View::value_type;

            if constexpr (std::is_same_v<OutString, std::basic_string_view<CharT>>) {
                const std::size_t pos = static_cast<std::size_t>(subMatch.first - base.begin());

                return OutString(base.data() + pos, static_cast<std::size_t>(subMatch.length()));
            }
            else {
                return OutString(subMatch.first, subMatch.first + subMatch.length());
            }
        }
    } // namespace details

    template <typename CharT, typename OutString = std::basic_string_view<CharT>>
    struct RegexMatchResult {
        std::vector<OutString> capturedGroups;
        OutString prefix;
        OutString suffix;

        RegexMatchResult(std::basic_string_view<CharT> base, const std::match_results<typename std::basic_string_view<CharT>::const_iterator>& match) {
            this->capturedGroups.reserve(match.size());

            for (const auto& subMatch : match) {
                this->capturedGroups.push_back(details::ToOutString<OutString>(base, subMatch));
            }
            this->prefix = details::ToOutString<OutString>(base, match.prefix());
            this->suffix = details::ToOutString<OutString>(base, match.suffix());
        }
    };

    template <typename CharT, typename OutString = std::basic_string_view<CharT>>
    inline std::vector<RegexMatchResult<CharT, OutString>> GetRegexMatches(std::basic_string_view<CharT> text, const std::basic_regex<CharT>& rx) {
        using It = typename std::basic_string_view<CharT>::const_iterator;
        std::regex_iterator<It> it(text.begin(), text.end(), rx), last;

        std::vector<RegexMatchResult<CharT, OutString>> results;
        for (; it != last; ++it) {
            results.emplace_back(text, *it);
        }
        return results;
    }

}

namespace universaldevkit::helpers::stdext::extensions::detail::stream {
    inline void LegacyDebugBreak() {
#if defined(_WIN32) && defined(_DEBUG)
        if (::IsDebuggerPresent()) {
            ::DebugBreak();
        }
#endif
    }

    inline void ThrowIfStreamNotOpened(const std::ios& stream, const std::string& context = "") {
        if (!stream.good()) {
            const std::string prefix = context.empty() ? "" : std::format("[{}] ", context);
            const std::string message = std::format("{}Stream is not open or in bad state", prefix);
            LegacyDebugBreak();
            throw std::exception(message.c_str());
        }
    }

    inline void ThrowIfStreamFailed(const std::ios& stream, const std::string& context = "") {
        if (stream.fail() || stream.bad()) {
            const std::string prefix = context.empty() ? "" : std::format("[{}] ", context);
            const std::string message = std::format("{}Stream failure (fail={}, bad={}, eof={})", prefix, stream.fail(), stream.bad(), stream.eof());
            LegacyDebugBreak();
            throw std::ios_base::failure(message);
        }
    }
}