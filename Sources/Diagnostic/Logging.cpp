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

#include <condition_variable>
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
            std::condition_variable conditionVariable;
            std::unordered_map<LoggerId, Entry> entries;
            std::size_t activeOperations = 0;
            std::uint64_t completedShutdowns = 0;
            bool isStopping = false;
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

        class BackendAccess final {
        public:
            explicit BackendAccess(LoggerId loggerId)
                : state{ details::GetState() } {
                std::scoped_lock lock{ this->state.mutex };
                if (!this->state.isStopping) {
                    const auto entry = this->state.entries.find(loggerId);
                    if (entry != this->state.entries.end() && entry->second.logger) {
                        this->logger = entry->second.logger;
                        ++this->state.activeOperations;
                        ++BackendAccess::currentThreadOperations;
                    }
                }
            }

            ~BackendAccess() noexcept {
                if (this->logger) {
                    // Release the backend before signaling that this operation has finished.
                    this->logger.reset();
                    --BackendAccess::currentThreadOperations;
                    std::scoped_lock lock{ this->state.mutex };
                    if (--this->state.activeOperations == 0) {
                        this->state.conditionVariable.notify_all();
                    }
                }
            }

            BackendAccess(const BackendAccess&) = delete;
            BackendAccess& operator=(const BackendAccess&) = delete;
            BackendAccess(BackendAccess&&) = delete;
            BackendAccess& operator=(BackendAccess&&) = delete;

            spdlog::logger* GetLogger() const noexcept {
                return this->logger.get();
            }

            static bool IsCurrentThreadActive() noexcept {
                return BackendAccess::currentThreadOperations != 0;
            }

        private:
            State& state;
            std::shared_ptr<spdlog::logger> logger;
            inline static thread_local std::size_t currentThreadOperations = 0;
        };

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

    LoggerInitResult Logger::Initialize(const LoggerOptions& loggerOptions, LoggerId loggerId) {
        auto loggerInitError = LoggerInitError::InitializationFailed;
        try {
            auto& state = details::GetState();
            std::scoped_lock lock{ state.mutex };
            if (state.isStopping) {
                return { LoggerInitError::ShutdownInProgress, {}, "Logger shutdown is in progress" };
            }
            if (state.entries.contains(loggerId) && state.entries.at(loggerId).logger) {
                return { LoggerInitError::AlreadyInitialized, {}, "Logger ID is already initialized" };
            }

            if (loggerOptions.minimumLevel < Level::Trace || loggerOptions.minimumLevel > Level::Off ||
                loggerOptions.logFolder < LogFolder::CurrentDirectory || loggerOptions.logFolder > LogFolder::ApplicationOrPackage ||
                (loggerOptions.fileMode != FileMode::Append && loggerOptions.fileMode != FileMode::Truncate) ||
                (!loggerOptions.filePath.empty() && (loggerOptions.maxFileSize == 0 || loggerOptions.maxFiles > 200000))) {
                return { LoggerInitError::InvalidOptions, {}, "Invalid level, folder, file mode or rotation limits" };
            }
#if !defined(_WIN32)
            if (loggerOptions.enableDebugger || loggerOptions.logFolder == LogFolder::Package) {
                return { LoggerInitError::UnsupportedPlatform, {}, "Requested Windows debugger or package folder on another platform" };
            }
#endif
            if (!loggerOptions.filePath.empty() && loggerOptions.logFolder == LogFolder::Package &&
                helpers::system::ApplicationPaths::GetPackageLocalDataDirectory().empty()) {
                return { LoggerInitError::PackageUnavailable, {}, "Application has no package identity" };
            }

            loggerInitError = LoggerInitError::DirectoryUnavailable;
            // Resolve and validate the destination before opening or truncating it.
            const auto filePath = details::ResolvePath(loggerOptions);
            for (const auto& [id, entry] : state.entries) {
                if (entry.logger && !entry.filePath.empty() && !filePath.empty() &&
                    std::filesystem::exists(filePath) && std::filesystem::equivalent(entry.filePath, filePath)) {
                    return { LoggerInitError::FileAlreadyUsed, {}, "A different logger ID already owns this file" };
                }
            }

            // Build the requested outputs; file ownership remains unique per ID.
            loggerInitError = LoggerInitError::InitializationFailed;
            spdlog::sink_ptr sink;
            if (filePath.empty() && !loggerOptions.enableConsole && !loggerOptions.enableDebugger) {
                sink = std::make_shared<spdlog::sinks::stderr_sink_mt>();
            }
            else if (!filePath.empty()) {
                loggerInitError = LoggerInitError::DirectoryUnavailable;
                std::filesystem::create_directories(filePath.parent_path());
                loggerInitError = LoggerInitError::FileOpenFailed;
                if (loggerOptions.fileMode == FileMode::Truncate) {
                    std::ofstream stream(filePath, std::ios::binary | std::ios::trunc);
                    if (!stream) {
                        return { LoggerInitError::FileOpenFailed, {}, "Cannot truncate log file" };
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
            loggerInitError = LoggerInitError::InitializationFailed;
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
                    return { LoggerInitError::ShutdownRegistrationFailed, {}, "Cannot register automatic logger shutdown" };
                }
                state.shutdownRegistered = true;
            }
            if (!filePath.empty() && loggerOptions.appendNewSession) {
                logger->info("========== New session started (logger {}) ==========", loggerId);
            }
            state.entries[loggerId] = details::Entry{ std::move(logger), filePath, loggerOptions.minimumLevel };
            return {};
        }
        catch (const std::bad_alloc&) {
            throw;
        }
        catch (const std::invalid_argument& invalidArgument) {
            return { LoggerInitError::InvalidOptions, {}, invalidArgument.what() };
        }
        catch (const std::system_error& systemError) {
            return { loggerInitError, systemError.code(), systemError.what() };
        }
        catch (const std::exception& exception) {
            return { loggerInitError, {}, exception.what() };
        }
        catch (...) {
            return { LoggerInitError::InitializationFailed, {}, "Unknown logger initialization failure" };
        }
    }

    void Logger::Shutdown() noexcept {
        static thread_local bool isShuttingDown = false;
        if (isShuttingDown || details::BackendAccess::IsCurrentThreadActive()) {
            details::EmergencyWrite("Diagnostic: Shutdown cannot run inside a backend operation");
            return;
        }
        try {
            // Stop admission atomically; concurrent Shutdown calls join this shutdown generation.
            auto& state = details::GetState();
            std::unique_lock lock{ state.mutex };
            if (state.isStopping) {
                const auto completedShutdowns = state.completedShutdowns;
                state.conditionVariable.wait(lock, [&state, completedShutdowns] {
                    return state.completedShutdowns != completedShutdowns;
                });
                return;
            }
            state.isStopping = true;
            isShuttingDown = true;
            state.conditionVariable.wait(lock, [&state] { return state.activeOperations == 0; });

            // No operation can acquire these backends now. Close without holding the registry lock.
            for (;;) {
                const auto entry = std::find_if(state.entries.begin(), state.entries.end(), [](const auto& item) {
                    return static_cast<bool>(item.second.logger);
                });
                if (entry == state.entries.end()) {
                    break;
                }
                auto logger = std::move(entry->second.logger);
                lock.unlock();
                try {
                    logger->flush();
                }
                catch (...) {
                    details::EmergencyWrite("Diagnostic: shutdown flush failed");
                }
                logger.reset();
                lock.lock();
            }

            // Keep levels for fallback logging and permit reinitialization only after file closure.
            state.isStopping = false;
            ++state.completedShutdowns;
            isShuttingDown = false;
            state.conditionVariable.notify_all();
        }
        catch (...) {
            isShuttingDown = false;
            details::EmergencyWrite("Diagnostic: shutdown failed");
        }
    }

    void Logger::Flush(LoggerId loggerId) noexcept {
        try {
            const details::BackendAccess backendAccess{ loggerId };
            if (backendAccess.GetLogger()) {
                backendAccess.GetLogger()->flush();
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
            const details::BackendAccess backendAccess{ loggerId };
            if (backendAccess.GetLogger()) {
                backendAccess.GetLogger()->log(
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