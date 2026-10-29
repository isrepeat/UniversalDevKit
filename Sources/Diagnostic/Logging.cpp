#include "../../Includes/Diagnostic/UniversalDevKit/Diagnostic/Logging.h"

#include <spdlog/sinks/rotating_file_sink.h>
#include <spdlog/sinks/stdout_color_sinks.h>
#include <spdlog/sinks/stdout_sinks.h>
#if defined(_WIN32)
#include <spdlog/sinks/msvc_sink.h>
#endif
#include <spdlog/logger.h>

#include <UniversalDevKit/Helpers/System/ApplicationPaths.h>
#include <UniversalDevKit/Helpers/Text/Unicode.h>

#if defined(_WIN32)
#include <Windows.h>
#elif defined(__linux__) || defined(__APPLE__)
#include <pthread.h>
#endif

#include <unordered_map>
#include <filesystem>
#include <algorithm>
#include <exception>
#include <stdexcept>
#include <cstdlib>
#include <fstream>
#include <cstdio>
#include <limits>
#include <memory>
#include <vector>
#include <mutex>

namespace universaldevkit::diagnostic {
    namespace details {
        struct Entry {
            std::shared_ptr<spdlog::logger> logger;
            std::filesystem::path filePath;
            Level minimumLevel = Level::Info;
        };

        struct State {
            std::mutex mutex;
            std::unordered_map<LoggerId, Entry> entries;
            bool shutdownRegistered = false;
        };

        State& GetState() {
            // Keep synchronization valid for late logging from static destructors.
            static State* state = new State;
            return *state;
        }

        spdlog::level::level_enum ToSpdlogLevel(Level level) noexcept {
            switch (level) {
            case Level::Trace: return spdlog::level::trace;
            case Level::Debug: return spdlog::level::debug;
            case Level::Info: return spdlog::level::info;
            case Level::Warning: return spdlog::level::warn;
            case Level::Error: return spdlog::level::err;
            case Level::Critical: return spdlog::level::critical;
            default: return spdlog::level::off;
            }
        }

        std::shared_ptr<spdlog::logger> GetLogger(LoggerId loggerId) {
            auto& state = details::GetState();
            std::scoped_lock lock{ state.mutex };
            auto entry = state.entries.find(loggerId);
            return entry == state.entries.end() ? nullptr : entry->second.logger;
        }

        std::filesystem::path ResolvePath(const LoggerOptions& loggerOptions) {
            if (loggerOptions.filePath.empty()) {
                return {};
            }
            if (loggerOptions.logFolder == LogFolder::CurrentDirectory) {
                return std::filesystem::weakly_canonical(std::filesystem::absolute(loggerOptions.filePath));
            }
            if (loggerOptions.filePath.is_absolute() || loggerOptions.filePath.has_root_path()) {
                throw std::invalid_argument("Folder-relative log paths must not be rooted");
            }
            for (const auto& part : loggerOptions.filePath) {
                if (part == "..") {
                    throw std::invalid_argument("Log path must stay inside the selected folder");
                }
            }
            std::filesystem::path folder;
            switch (loggerOptions.logFolder) {
            case LogFolder::Application:
                folder = helpers::system::ApplicationPaths::GetExecutableDirectory();
                break;
            case LogFolder::Package:
                folder = helpers::system::ApplicationPaths::GetPackageLocalDataDirectory();
                if (folder.empty()) {
                    throw std::runtime_error("Application has no package identity");
                }
                break;
            case LogFolder::ApplicationOrPackage:
                folder = helpers::system::ApplicationPaths::GetPackageLocalDataDirectory();
                if (folder.empty()) {
                    folder = helpers::system::ApplicationPaths::GetExecutableDirectory();
                }
                break;
            default:
                throw std::invalid_argument("Unknown log folder");
            }
            return std::filesystem::weakly_canonical(folder / loggerOptions.filePath);
        }

        bool SetCurrentThreadName(std::string_view name) noexcept {
            try {
                if (name.find('\0') != std::string_view::npos) {
                    return false;
                }
#if defined(_WIN32)
                if (name.empty()) {
                    return SUCCEEDED(::SetThreadDescription(::GetCurrentThread(), L""));
                }
                if (name.size() > static_cast<std::size_t>((std::numeric_limits<int>::max)())) {
                    return false;
                }
                const auto length = ::MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, name.data(), static_cast<int>(name.size()), nullptr, 0);
                if (length == 0) {
                    return false;
                }
                std::wstring wideName(static_cast<std::size_t>(length), L'\0');
                if (::MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, name.data(), static_cast<int>(name.size()), wideName.data(), length) == 0) {
                    return false;
                }
                return SUCCEEDED(::SetThreadDescription(::GetCurrentThread(), wideName.c_str()));
#elif defined(__linux__) || defined(__APPLE__)
                // The OS limit includes the terminator; preserve complete UTF-8 characters.
#if defined(__linux__)
                constexpr std::size_t limit = 15;
#else
                constexpr std::size_t limit = 63;
#endif
                auto length = (std::min)(name.size(), limit);
                while (length < name.size() && length > 0 && (static_cast<unsigned char>(name[length]) & 0xC0) == 0x80) {
                    --length;
                }
                const std::string shortName(name.substr(0, length));
#if defined(__linux__)
                return ::pthread_setname_np(::pthread_self(), shortName.c_str()) == 0;
#else
                return ::pthread_setname_np(shortName.c_str()) == 0;
#endif
#else
                return false;
#endif
            }
            catch (...) {
                return false;
            }
        }

        void EmergencyWrite(std::string_view message) noexcept {
            // No allocation, callbacks or recursive logging in the fallback.
            std::fwrite(message.data(), 1, message.size(), stderr);
            std::fputc('\n', stderr);
            std::fflush(stderr);
        }
    } // namespace details

    ThreadScope::ThreadScope(std::wstring name, std::source_location sourceLocation, LoggerId loggerId)
        : ThreadScope(helpers::text::Unicode::ToUtf8(name), sourceLocation, loggerId) {
    }

    ThreadScope::ThreadScope(std::string name, std::source_location sourceLocation, LoggerId loggerId) noexcept
        : name{ std::move(name) }
        , sourceLocation{ sourceLocation }
        , loggerId{ loggerId }
        , active{ Logger::ShouldLog(Level::Debug, loggerId) } {
        if (!details::SetCurrentThreadName(this->name)) {
            Logger::LogForId(this->loggerId, Level::Warning, "Thread", this->sourceLocation, "Cannot set thread name '{}'", this->name);
        }
        if (this->active) {
            Logger::LogForId(this->loggerId, Level::Debug, "Thread", this->sourceLocation, "Thread START '{}'", this->name);
        }
    }

    ThreadScope::~ThreadScope() noexcept {
        if (this->active) {
            Logger::LogForId(this->loggerId, Level::Debug, "Thread", this->sourceLocation, "Thread END '{}'", this->name);
        }
    }

    LogScope::LogScope(std::string category, std::wstring name, std::source_location sourceLocation, LoggerId loggerId)
        : LogScope(std::move(category), helpers::text::Unicode::ToUtf8(name), sourceLocation, loggerId) {
    }

    LogScope::LogScope(std::string category, std::string name, std::source_location sourceLocation, LoggerId loggerId) noexcept
        : category{ std::move(category) }
        , name{ std::move(name) }
        , sourceLocation{ sourceLocation }
        , loggerId{ loggerId }
        , started{ std::chrono::steady_clock::now() }
        , active{ Logger::ShouldLog(Level::Debug, loggerId) }
        , exceptionsOnEntry{ std::uncaught_exceptions() } {
        if (this->active) {
            Logger::LogForId(this->loggerId, Level::Debug, this->category, this->sourceLocation, ">> {}", this->name);
        }
    }

    LogScope::~LogScope() noexcept {
        if (this->active) {
            const auto elapsed = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - this->started);
            Logger::LogForId(
                this->loggerId,
                Level::Debug,
                this->category,
                this->sourceLocation,
                "<< {} ({} us{})",
                this->name,
                elapsed.count(),
                std::uncaught_exceptions() > this->exceptionsOnEntry ? ", exception" : ""
            );
        }
    }

    bool Logger::Initialize(const LoggerOptions& loggerOptions, LoggerId loggerId) noexcept {
        try {
            auto& state = details::GetState();
            std::scoped_lock lock{ state.mutex };
            if (state.entries.contains(loggerId) && state.entries.at(loggerId).logger) {
                return false;
            }

            // Resolve and validate the destination before opening or truncating it.
            const auto filePath = details::ResolvePath(loggerOptions);
            for (const auto& [id, entry] : state.entries) {
                if (entry.logger && !entry.filePath.empty() && !filePath.empty() &&
                    std::filesystem::exists(filePath) && std::filesystem::equivalent(entry.filePath, filePath)) {
                    throw std::invalid_argument("A logger already owns this file");
                }
            }
            if (!filePath.empty() && loggerOptions.maxFileSize == 0) {
                throw std::invalid_argument("maxFileSize must be positive");
            }

            // Build the requested outputs; file ownership remains unique per ID.
#if !defined(_WIN32)
            if (loggerOptions.enableDebugger) {
                throw std::invalid_argument("Debugger output is supported only on Windows");
            }
#endif
            spdlog::sink_ptr sink;
            if (filePath.empty() && !loggerOptions.enableConsole && !loggerOptions.enableDebugger) {
                sink = std::make_shared<spdlog::sinks::stderr_sink_mt>();
            }
            else if (!filePath.empty()) {
                std::filesystem::create_directories(filePath.parent_path());
                if (loggerOptions.fileMode == FileMode::Truncate) {
                    std::ofstream stream(filePath, std::ios::binary | std::ios::trunc);
                    if (!stream) {
                        throw std::runtime_error("Cannot truncate log file");
                    }
                }
                const bool oversized = std::filesystem::exists(filePath) &&
                    std::filesystem::file_size(filePath) > loggerOptions.maxFileSize;
                sink = std::make_shared<spdlog::sinks::rotating_file_sink_mt>(
                    filePath.native(),
                    loggerOptions.maxFileSize,
                    loggerOptions.maxFiles,
                    oversized
                );
            }
            std::vector<spdlog::sink_ptr> sinks;
            if (sink) {
                sink->set_pattern("[%Y-%m-%d %H:%M:%S.%e] [%l] [%t] {%s:%# %!} %v");
                sinks.push_back(std::move(sink));
            }
            if (loggerOptions.enableConsole) {
                auto consoleSink = std::make_shared<spdlog::sinks::stderr_color_sink_mt>(
                    loggerOptions.colorConsole ? spdlog::color_mode::automatic : spdlog::color_mode::never
                );
                consoleSink->set_pattern("%^[%Y-%m-%d %H:%M:%S.%e] [%l] [%t] {%s:%# %!} %v%$");
                sinks.push_back(std::move(consoleSink));
            }
#if defined(_WIN32)
            if (loggerOptions.enableDebugger) {
                auto debuggerSink = std::make_shared<spdlog::sinks::msvc_sink_mt>();
                debuggerSink->set_pattern("[%Y-%m-%d %H:%M:%S.%e] [%l] [%t] {%s:%# %!} %v");
                sinks.push_back(std::move(debuggerSink));
            }
#endif
            auto logger = std::make_shared<spdlog::logger>("Diagnostic." + std::to_string(loggerId), sinks.begin(), sinks.end());
            logger->set_level(spdlog::level::trace);
            logger->flush_on(spdlog::level::trace);
            logger->set_error_handler([](const std::string&) {
                details::EmergencyWrite("Diagnostic: spdlog write failed");
            });
            // Register once, including when the host explicitly shuts down and restarts logging.
            if (!state.shutdownRegistered) {
                if (std::atexit(&Logger::Shutdown) != 0) {
                    details::EmergencyWrite("Diagnostic: shutdown registration failed");
                    return false;
                }
                state.shutdownRegistered = true;
            }
            if (!filePath.empty() && loggerOptions.appendNewSession) {
                logger->info("========== New session started (logger {}) ==========", loggerId);
            }
            state.entries[loggerId] = details::Entry{ std::move(logger), filePath, loggerOptions.minimumLevel };
            return true;
        }
        catch (...) {
            details::EmergencyWrite("Diagnostic: initialization failed");
            return false;
        }
    }

    void Logger::Shutdown() noexcept {
        try {
            std::vector<std::shared_ptr<spdlog::logger>> loggers;
            {
                auto& state = details::GetState();
                std::scoped_lock lock{ state.mutex };
                loggers.reserve(state.entries.size());
                for (auto& [id, entry] : state.entries) {
                    if (entry.logger) {
                        loggers.push_back(std::move(entry.logger));
                    }
                }
            }
            for (const auto& logger : loggers) {
                logger->flush();
            }
        }
        catch (...) {
            details::EmergencyWrite("Diagnostic: shutdown failed");
        }
    }

    void Logger::Flush(LoggerId loggerId) noexcept {
        try {
            if (auto logger = details::GetLogger(loggerId)) {
                logger->flush();
            }
        }
        catch (...) {
            details::EmergencyWrite("Diagnostic: flush failed");
        }
    }

    void Logger::SetLevel(Level level, LoggerId loggerId) noexcept {
        try {
            auto& state = details::GetState();
            std::scoped_lock lock{ state.mutex };
            state.entries[loggerId].minimumLevel = level;
        }
        catch (...) {
            details::EmergencyWrite("Diagnostic: level update failed");
        }
    }

    bool Logger::ShouldLog(Level level, LoggerId loggerId) noexcept {
        try {
            auto& state = details::GetState();
            std::scoped_lock lock{ state.mutex };
            const auto entry = state.entries.find(loggerId);
            const auto minimumLevel = entry == state.entries.end() ? Level::Info : entry->second.minimumLevel;
            return level >= minimumLevel && level < Level::Off;
        }
        catch (...) {
            return false;
        }
    }

    void Logger::Write(
        Level level,
        std::string_view category,
        std::wstring_view message,
        std::source_location sourceLocation,
        LoggerId loggerId
    ) noexcept {
        if (!Logger::ShouldLog(level, loggerId)) {
            return;
        }
        try {
            Logger::Write(level, category, helpers::text::Unicode::ToUtf8(message), sourceLocation, loggerId);
        }
        catch (...) {
            Logger::Write(Level::Error, "Diagnostic", "Failed to convert wide log message to UTF-8", sourceLocation, loggerId);
        }
    }

    void Logger::Write(
        Level level,
        std::string_view category,
        std::string_view message,
        std::source_location sourceLocation,
        LoggerId loggerId
    ) noexcept {
        if (!Logger::ShouldLog(level, loggerId)) {
            return;
        }
        try {
            if (auto logger = details::GetLogger(loggerId)) {
                logger->log(
                    spdlog::source_loc{ sourceLocation.file_name(), static_cast<int>(sourceLocation.line()), sourceLocation.function_name() },
                    details::ToSpdlogLevel(level),
                    "[{}] {}",
                    spdlog::string_view_t{ category.data(), category.size() },
                    spdlog::string_view_t{ message.data(), message.size() }
                );
            }
            else {
                details::EmergencyWrite(message);
            }
        }
        catch (...) {
            details::EmergencyWrite("Diagnostic: write failed");
        }
    }
}