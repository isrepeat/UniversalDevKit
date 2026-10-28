#pragma once
#if defined(_WIN32) && defined(_DEBUG)
#pragma push_macro("NOMINMAX")
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <Windows.h>
#pragma pop_macro("NOMINMAX")
#endif

#include <exception>
#include <fstream>
#include <format>
#include <string>

namespace universaldevkit::helpers::stream {
    namespace detail {
        inline void DebugBreakIfAttached() {
#if defined(_WIN32) && defined(_DEBUG)
            if (::IsDebuggerPresent()) {
                ::DebugBreak();
            }
#endif
        }
    } // namespace detail

    inline void ThrowIfStreamNotOpened(const std::ios& stream, const std::string& context = "") {
        if (!stream.good()) {
            const std::string prefix = context.empty() ? "" : std::format("[{}] ", context);
            const std::string message = std::format("{}Stream is not open or in bad state", prefix);
            detail::DebugBreakIfAttached();
            throw std::exception(message.c_str());
        }
    }

    inline void ThrowIfStreamFailed(const std::ios& stream, const std::string& context = "") {
        if (stream.fail() || stream.bad()) {
            const std::string prefix = context.empty() ? "" : std::format("[{}] ", context);
            const std::string message = std::format("{}Stream failure (fail={}, bad={}, eof={})", prefix, stream.fail(), stream.bad(), stream.eof());
            detail::DebugBreakIfAttached();
            throw std::ios_base::failure(message);
        }
    }
}