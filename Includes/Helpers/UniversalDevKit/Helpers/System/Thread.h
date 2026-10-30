#pragma once
#include <UniversalDevKit/Platform.h>

#if UNIVERSALDEVKIT_PLATFORM_WINDOWS
#include <Windows.h>
#elif UNIVERSALDEVKIT_PLATFORM_POSIX
#include <pthread.h>
#endif

#include "../Text/Unicode.h"

#include <string_view>
#include <algorithm>
#include <string>

namespace universaldevkit::helpers::system {
    class Thread final {
    public:
        Thread() = delete;

        // The UTF-8 name is shortened at a character boundary when the OS imposes a limit.
        static bool SetCurrentThreadName(std::string_view name) noexcept {
            try {
                if (name.find('\0') != std::string_view::npos) {
                    return false;
                }
#if UNIVERSALDEVKIT_PLATFORM_WINDOWS
                const auto wideName = text::Unicode::FromUtf8(name);
                return SUCCEEDED(::SetThreadDescription(::GetCurrentThread(), wideName.c_str()));
#elif UNIVERSALDEVKIT_PLATFORM_POSIX
#if UNIVERSALDEVKIT_PLATFORM_MACOS
                constexpr std::size_t limit = 63;
#else
                constexpr std::size_t limit = 15;
#endif
                auto length = (std::min)(name.size(), limit);
                while (length < name.size() && length > 0 && (static_cast<unsigned char>(name[length]) & 0xC0) == 0x80) {
                    --length;
                }
                const std::string shortName(name.substr(0, length));
#if UNIVERSALDEVKIT_PLATFORM_MACOS
                return ::pthread_setname_np(shortName.c_str()) == 0;
#else
                return ::pthread_setname_np(::pthread_self(), shortName.c_str()) == 0;
#endif
#else
                return false;
#endif
            }
            catch (...) {
                return false;
            }
        }
    };
}