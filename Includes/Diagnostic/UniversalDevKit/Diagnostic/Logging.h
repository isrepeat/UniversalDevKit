#pragma once
#include "Export.h"

#include <source_location>
#include <string_view>
#include <utility>
#include <format>

namespace universaldevkit::diagnostic {
    enum class Level {
        Trace,
        Debug,
        Info,
        Warning,
        Error,
        Critical,
        Off
    };

    struct Options {
        Level minimumLevel = Level::Info;
    };

    class Logger final {
    public:
        Logger() = delete;

        // The host initializes logging; normal exit calls Shutdown automatically.
        static UNIVERSALDEVKIT_DIAGNOSTIC_API bool Initialize(const Options& options = {}) noexcept;
        static UNIVERSALDEVKIT_DIAGNOSTIC_API void Shutdown() noexcept;
        static UNIVERSALDEVKIT_DIAGNOSTIC_API void Flush() noexcept;
        static UNIVERSALDEVKIT_DIAGNOSTIC_API void SetLevel(Level level) noexcept;
        static UNIVERSALDEVKIT_DIAGNOSTIC_API bool ShouldLog(Level level) noexcept;
        static UNIVERSALDEVKIT_DIAGNOSTIC_API void Write(
            Level level,
            std::string_view category,
            std::string_view message,
            std::source_location sourceLocation = std::source_location::current()
        ) noexcept;

        // Formatting stays in the caller; no spdlog or fmt types cross the DLL boundary.
        template<typename... TArgs>
        static void Log(
            Level level,
            std::string_view category,
            std::source_location sourceLocation,
            std::format_string<TArgs...> format,
            TArgs&&... args
        ) noexcept {
            if (!Logger::ShouldLog(level)) {
                return;
            }
            try {
                Logger::Write(level, category, std::format(format, std::forward<TArgs>(args)...), sourceLocation);
            }
            catch (...) {
                Logger::Write(Level::Error, "Diagnostic", "Failed to format log message", sourceLocation);
            }
        }
    };
}

// Check before evaluating category and formatting arguments.
#define UDK_LOG_AT(level, category, ...) \
    do { \
        const auto udkDiagnosticLogLevel = (level); \
        if (::universaldevkit::diagnostic::Logger::ShouldLog(udkDiagnosticLogLevel)) { \
            ::universaldevkit::diagnostic::Logger::Log( \
                udkDiagnosticLogLevel, \
                category, \
                ::std::source_location::current(), \
                __VA_ARGS__); \
        } \
    } while (false)

#define UDK_LOG_TRACE(category, ...) UDK_LOG_AT(::universaldevkit::diagnostic::Level::Trace, category, __VA_ARGS__)
#define UDK_LOG_DEBUG(category, ...) UDK_LOG_AT(::universaldevkit::diagnostic::Level::Debug, category, __VA_ARGS__)
#define UDK_LOG_INFO(category, ...) UDK_LOG_AT(::universaldevkit::diagnostic::Level::Info, category, __VA_ARGS__)
#define UDK_LOG_WARNING(category, ...) UDK_LOG_AT(::universaldevkit::diagnostic::Level::Warning, category, __VA_ARGS__)
#define UDK_LOG_ERROR(category, ...) UDK_LOG_AT(::universaldevkit::diagnostic::Level::Error, category, __VA_ARGS__)
#define UDK_LOG_CRITICAL(category, ...) UDK_LOG_AT(::universaldevkit::diagnostic::Level::Critical, category, __VA_ARGS__)