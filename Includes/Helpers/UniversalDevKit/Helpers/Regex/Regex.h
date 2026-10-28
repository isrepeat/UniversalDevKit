#pragma once
#include <string_view>
#include <type_traits>
#include <optional>
#include <string>
#include <vector>
#include <regex>

namespace universaldevkit::helpers::regex {
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
        inline OutString ToOutString(View base, // The same text used by regex_search.
                                     const std::sub_match<It>& subMatch) {
            using CharT = typename View::value_type;

            // Why the source view is passed explicitly:
            // sub_match stores iterators [first, last) into the original text. Constructing
            // a string_view directly from these iterators can trigger a static analyzer
            // warning about a temporary sub_match, although the characters belong to the source.
            // Bind the view explicitly to the source buffer passed to regex_search.
            // This makes the storage relationship explicit:
            //   1) The view points into base.data(); callers must keep that storage alive.
            //   2) Avoid a misleading warning about a dangling view.
            //
            // Important: base must refer to the same buffer used by regex_search.
            // Otherwise the calculated position is invalid.
            if constexpr (std::is_same_v<OutString, std::basic_string_view<CharT>>) {
                // Calculate the substring position relative to the source view.
                const std::size_t pos = static_cast<std::size_t>(subMatch.first - base.begin());

                return OutString(base.data() + pos, static_cast<std::size_t>(subMatch.length()));
            }
            else {
                // For owning strings, copy characters from the matched range.
                // Avoid subMatch.str() to eliminate an intermediate std::basic_string.
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

            // All submatches, including prefix and suffix, refer to the original text.
            // Build OutString through base to associate views with the source storage.
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
            // Pass the original text containing all matched substrings.
            results.emplace_back(text, *it);
        }
        return results;
    }

    template <typename CharT, typename OutString = std::basic_string_view<CharT>>
    inline std::optional<RegexMatchResult<CharT, OutString>> GetRegexMatch(std::basic_string_view<CharT> text, const std::basic_regex<CharT>& rx) {
        using It = typename std::basic_string_view<CharT>::const_iterator;
        std::match_results<It> match;

        if (std::regex_search(text.begin(), text.end(), match, rx)) {
            // Pass the original text containing all matched substrings.
            return RegexMatchResult<CharT, OutString>(text, match);
        }
        return std::nullopt;
    }

    inline bool FindInsideTagWithRegex(std::wstring_view text, std::wstring_view tag, const std::wregex& innerRx) {
        const std::wregex rx(std::wstring(L"([^<]*)<") + std::wstring(tag) + L"[^>]*>(.+?)<[/]" + std::wstring(tag) + L">([^<]*)");

        auto matches = GetRegexMatches<wchar_t, std::wstring_view>(text, rx);
        for (auto& match : matches) {
            details::match_t<wchar_t> inner;

            const auto& body = match.capturedGroups.size() > 2 ? match.capturedGroups[2] : std::wstring_view{};
            if (std::regex_search(body.begin(), body.end(), inner, innerRx)) {
                return true;
            }
        }
        return false;
    }

    inline bool FindInsideAnyTagWithRegex(std::wstring_view text, const std::wregex& innerRx) {
        const std::wstring anyTag = L"[^>]*";
        const std::wregex rx(L"([^<]*)<" + anyTag + L">(.+?)<[/]" + anyTag + L">([^<]*)");

        auto matches = GetRegexMatches<wchar_t, std::wstring_view>(text, rx);
        for (const auto& match : matches) {
            details::match_t<wchar_t> inner;

            const auto& body = match.capturedGroups.size() > 2 ? match.capturedGroups[2] : std::wstring_view{};
            if (std::regex_search(body.begin(), body.end(), inner, innerRx)) {
                return true;
            }
        }
        return false;
    }
}