#pragma once
#include "Export.h"

#include <source_location>
#include <string_view>
#include <filesystem>
#include <cstddef>
#include <cstdint>
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

    using LoggerId = std::uint32_t;

    enum class LogFolder {
        CurrentDirectory,
        Application,
        Package,
        ApplicationOrPackage
    };

    enum class FileMode {
        Append,
        Truncate
    };

    struct LoggerOptions {
        Level minimumLevel = Level::Info;
        std::filesystem::path filePath;
        LogFolder logFolder = LogFolder::CurrentDirectory;
        FileMode fileMode = FileMode::Append;
        std::size_t maxFileSize = 10 * 1024 * 1024;
        std::size_t maxFiles = 1;
        bool appendNewSession = true;
    };

    class Logger final {
    public:
        Logger() = delete;

        // The host initializes logging; normal exit calls Shutdown automatically.
        static UNIVERSALDEVKIT_DIAGNOSTIC_API bool Initialize(const LoggerOptions& loggerOptions = {}, LoggerId loggerId = 0) noexcept;
        static UNIVERSALDEVKIT_DIAGNOSTIC_API void Shutdown() noexcept;
        static UNIVERSALDEVKIT_DIAGNOSTIC_API void Flush(LoggerId loggerId = 0) noexcept;
        static UNIVERSALDEVKIT_DIAGNOSTIC_API void SetLevel(Level level, LoggerId loggerId = 0) noexcept;
        static UNIVERSALDEVKIT_DIAGNOSTIC_API bool ShouldLog(Level level, LoggerId loggerId = 0) noexcept;
        static UNIVERSALDEVKIT_DIAGNOSTIC_API void Write(
            Level level,
            std::string_view category,
            std::string_view message,
            std::source_location sourceLocation = std::source_location::current(),
            LoggerId loggerId = 0
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
            Logger::LogForId(0, level, category, sourceLocation, format, std::forward<TArgs>(args)...);
        }

        template<typename... TArgs>
        static void LogForId(
            LoggerId loggerId,
            Level level,
            std::string_view category,
            std::source_location sourceLocation,
            std::format_string<TArgs...> format,
            TArgs&&... args
        ) noexcept {
            if (!Logger::ShouldLog(level, loggerId)) {
                return;
            }
            try {
                Logger::Write(level, category, std::format(format, std::forward<TArgs>(args)...), sourceLocation, loggerId);
            }
            catch (...) {
                Logger::Write(Level::Error, "Diagnostic", "Failed to format log message", sourceLocation, loggerId);
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

#define UDK_LOG_AT_N(loggerId, level, category, ...) \
    do { \
        const auto udkDiagnosticLoggerId = (loggerId); \
        const auto udkDiagnosticLogLevel = (level); \
        if (::universaldevkit::diagnostic::Logger::ShouldLog(udkDiagnosticLogLevel, udkDiagnosticLoggerId)) { \
            ::universaldevkit::diagnostic::Logger::LogForId( \
                udkDiagnosticLoggerId, \
                udkDiagnosticLogLevel, \
                category, \
                ::std::source_location::current(), \
                __VA_ARGS__); \
        } \
    } while (false)

#define UDK_LOG_TRACE_N(id, category, ...) UDK_LOG_AT_N(id, ::universaldevkit::diagnostic::Level::Trace, category, __VA_ARGS__)
#define UDK_LOG_DEBUG_N(id, category, ...) UDK_LOG_AT_N(id, ::universaldevkit::diagnostic::Level::Debug, category, __VA_ARGS__)
#define UDK_LOG_INFO_N(id, category, ...) UDK_LOG_AT_N(id, ::universaldevkit::diagnostic::Level::Info, category, __VA_ARGS__)
#define UDK_LOG_WARNING_N(id, category, ...) UDK_LOG_AT_N(id, ::universaldevkit::diagnostic::Level::Warning, category, __VA_ARGS__)
#define UDK_LOG_ERROR_N(id, category, ...) UDK_LOG_AT_N(id, ::universaldevkit::diagnostic::Level::Error, category, __VA_ARGS__)
#define UDK_LOG_CRITICAL_N(id, category, ...) UDK_LOG_AT_N(id, ::universaldevkit::diagnostic::Level::Critical, category, __VA_ARGS__)