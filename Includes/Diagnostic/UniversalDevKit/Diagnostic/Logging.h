#pragma once
#include "Export.h"

#include <source_location>
#include <system_error>
#include <string_view>
#include <filesystem>
#include <cstddef>
#include <cstdint>
#include <utility>
#include <chrono>
#include <format>
#include <string>

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
        bool enableConsole = false;
        bool enableDebugger = false;
        bool colorConsole = true;
    };

    enum class LoggerInitError {
        None,
        AlreadyInitialized,
        FileAlreadyUsed,
        InvalidOptions,
        DirectoryUnavailable,
        FileOpenFailed,
        PackageUnavailable,
        UnsupportedPlatform,
        ShutdownRegistrationFailed,
        InitializationFailed,
        ShutdownInProgress
    };

    struct LoggerInitResult {
        LoggerInitError error = LoggerInitError::None;
        std::error_code systemError;
        std::string message;

        explicit operator bool() const noexcept {
            return this->error == LoggerInitError::None;
        }
    };

    struct LogContext {
        std::string className;
        std::string instanceName;

        std::string GetCategory() const {
            return this->instanceName.empty() ? this->className : std::format("{}[{}]", this->className, this->instanceName);
        }
    };

    class Logger final {
    public:
        Logger() = delete;

        // The host initializes logging; normal exit calls Shutdown automatically.
        [[nodiscard]] static UNIVERSALDEVKIT_DIAGNOSTIC_API LoggerInitResult Initialize(const LoggerOptions& loggerOptions = {}, LoggerId loggerId = 0);
        // Waits for admitted backend writes/flushes and releases files before returning.
        // Concurrent new writes use fallback; callers must still quiesce before DLL unload.
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
        static UNIVERSALDEVKIT_DIAGNOSTIC_API void Write(
            Level level,
            std::string_view category,
            std::wstring_view message,
            std::source_location sourceLocation = std::source_location::current(),
            LoggerId loggerId = 0
        ) noexcept;

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

        template<typename... TArgs>
        static void Log(
            Level level,
            std::string_view category,
            std::source_location sourceLocation,
            std::wformat_string<TArgs...> format,
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
            std::wformat_string<TArgs...> format,
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

    class ThreadScope final {
    public:
        ThreadScope() = default;
        UNIVERSALDEVKIT_DIAGNOSTIC_API ThreadScope(
            std::string name,
            std::source_location sourceLocation,
            LoggerId loggerId = 0
        ) noexcept;
        UNIVERSALDEVKIT_DIAGNOSTIC_API ~ThreadScope() noexcept;
        UNIVERSALDEVKIT_DIAGNOSTIC_API ThreadScope(
            std::wstring name,
            std::source_location sourceLocation,
            LoggerId loggerId = 0
        );

        ThreadScope(const ThreadScope&) = delete;
        ThreadScope& operator=(const ThreadScope&) = delete;
        ThreadScope(ThreadScope&&) = delete;
        ThreadScope& operator=(ThreadScope&&) = delete;

    private:
        std::string name;
        std::source_location sourceLocation;
        LoggerId loggerId = 0;
        bool active = false;
    };

    class LogScope final {
    public:
        LogScope() = default;
        UNIVERSALDEVKIT_DIAGNOSTIC_API LogScope(
            std::string category,
            std::string name,
            std::source_location sourceLocation,
            LoggerId loggerId = 0
        ) noexcept;
        UNIVERSALDEVKIT_DIAGNOSTIC_API ~LogScope() noexcept;
        UNIVERSALDEVKIT_DIAGNOSTIC_API LogScope(
            std::string category,
            std::wstring name,
            std::source_location sourceLocation,
            LoggerId loggerId = 0
        );

        LogScope(const LogScope&) = delete;
        LogScope& operator=(const LogScope&) = delete;
        LogScope(LogScope&&) = delete;
        LogScope& operator=(LogScope&&) = delete;

    private:
        std::string category;
        std::string name;
        std::source_location sourceLocation;
        LoggerId loggerId = 0;
        std::chrono::steady_clock::time_point started;
        bool active = false;
        int exceptionsOnEntry = 0;
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

// Place at the start of a class; subsequent declarations resume private access.
#define UDK_LOG_CLASS(className) \
    private: \
        ::universaldevkit::diagnostic::LogContext logContext{ #className, {} }; \
    public: \
        const ::universaldevkit::diagnostic::LogContext& __LgCtx() const noexcept { return this->logContext; } \
        void SetLogInstanceName(::std::string name) { this->logContext.instanceName = ::std::move(name); } \
    private:

#define UDK_LOG_TRACE_C(...) UDK_LOG_TRACE(this->__LgCtx().GetCategory(), __VA_ARGS__)
#define UDK_LOG_TRACE_S(logContext, ...) UDK_LOG_TRACE((logContext).GetCategory(), __VA_ARGS__)
#define UDK_LOG_DEBUG_C(...) UDK_LOG_DEBUG(this->__LgCtx().GetCategory(), __VA_ARGS__)
#define UDK_LOG_DEBUG_S(logContext, ...) UDK_LOG_DEBUG((logContext).GetCategory(), __VA_ARGS__)
#define UDK_LOG_INFO_C(...) UDK_LOG_INFO(this->__LgCtx().GetCategory(), __VA_ARGS__)
#define UDK_LOG_INFO_S(logContext, ...) UDK_LOG_INFO((logContext).GetCategory(), __VA_ARGS__)
#define UDK_LOG_WARNING_C(...) UDK_LOG_WARNING(this->__LgCtx().GetCategory(), __VA_ARGS__)
#define UDK_LOG_WARNING_S(logContext, ...) UDK_LOG_WARNING((logContext).GetCategory(), __VA_ARGS__)
#define UDK_LOG_ERROR_C(...) UDK_LOG_ERROR(this->__LgCtx().GetCategory(), __VA_ARGS__)
#define UDK_LOG_ERROR_S(logContext, ...) UDK_LOG_ERROR((logContext).GetCategory(), __VA_ARGS__)
#define UDK_LOG_CRITICAL_C(...) UDK_LOG_CRITICAL(this->__LgCtx().GetCategory(), __VA_ARGS__)
#define UDK_LOG_CRITICAL_S(logContext, ...) UDK_LOG_CRITICAL((logContext).GetCategory(), __VA_ARGS__)

#define UDK_DIAGNOSTIC_JOIN_INNER(left, right) left##right
#define UDK_DIAGNOSTIC_JOIN(left, right) UDK_DIAGNOSTIC_JOIN_INNER(left, right)

// The lambda formats the scope label once, and only when Debug is enabled.
#define UDK_LOG_SCOPE_N(id, category, ...) \
    auto UDK_DIAGNOSTIC_JOIN(udkLogScope, __COUNTER__) = [&](::std::source_location udkSourceLocation) -> ::universaldevkit::diagnostic::LogScope { \
        const auto udkLoggerId = (id); \
        if (!::universaldevkit::diagnostic::Logger::ShouldLog(::universaldevkit::diagnostic::Level::Debug, udkLoggerId)) { \
            return {}; \
        } \
        try { \
            return { ::std::string(category), ::std::format(__VA_ARGS__), udkSourceLocation, udkLoggerId }; \
        } catch (...) { \
            return {}; \
        } \
    }(::std::source_location::current())

#define UDK_LOG_SCOPE(category, ...) UDK_LOG_SCOPE_N(0, category, __VA_ARGS__)
#define UDK_LOG_FUNCTION_SCOPE(category) UDK_LOG_SCOPE(category, "{}", udkSourceLocation.function_name())
#define UDK_LOG_FUNCTION_ENTER(category) UDK_LOG_DEBUG(category, ">> {}", ::std::source_location::current().function_name())
#define UDK_LOG_SCOPE_C(...) UDK_LOG_SCOPE(this->__LgCtx().GetCategory(), __VA_ARGS__)
#define UDK_LOG_FUNCTION_SCOPE_C() UDK_LOG_FUNCTION_SCOPE(this->__LgCtx().GetCategory())
#define UDK_LOG_FUNCTION_ENTER_C() UDK_LOG_FUNCTION_ENTER(this->__LgCtx().GetCategory())

// Naming is independent of Debug filtering; evaluate the supplied name once.
#define UDK_LOG_THREAD_N(id, name) \
    auto UDK_DIAGNOSTIC_JOIN(udkThreadScope, __COUNTER__) = [&](::std::source_location udkSourceLocation) -> ::universaldevkit::diagnostic::ThreadScope { \
        try { \
            return { ::std::basic_string(name), udkSourceLocation, (id) }; \
        } catch (...) { \
            return {}; \
        } \
    }(::std::source_location::current())

#define UDK_LOG_THREAD(name) UDK_LOG_THREAD_N(0, name)