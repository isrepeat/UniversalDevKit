#include "../../Includes/Diagnostic/UniversalDevKit/Diagnostic/Logging.h"

#include <spdlog/sinks/rotating_file_sink.h>
#include <spdlog/sinks/stdout_sinks.h>
#include <spdlog/logger.h>

#include <UniversalDevKit/Helpers/System/ApplicationPaths.h>

#if defined(_WIN32)
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <Windows.h>
#include <appmodel.h>
#endif

#include <unordered_map>
#include <filesystem>
#include <stdexcept>
#include <cstdlib>
#include <fstream>
#include <cstdio>
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

        void EmergencyWrite(std::string_view message) noexcept {
            // No allocation, callbacks or recursive logging in the fallback.
            std::fwrite(message.data(), 1, message.size(), stderr);
            std::fputc('\n', stderr);
            std::fflush(stderr);
        }
    } // namespace details

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

            // Each ID owns one sink; all file access goes through that sink.
            spdlog::sink_ptr sink;
            if (filePath.empty()) {
                sink = std::make_shared<spdlog::sinks::stderr_sink_mt>();
            }
            else {
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
            auto logger = std::make_shared<spdlog::logger>("Diagnostic." + std::to_string(loggerId), std::move(sink));
            logger->set_pattern("[%Y-%m-%d %H:%M:%S.%e] [%l] [%t] {%s:%# %!} %v");
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