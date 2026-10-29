#include <UniversalDevKit/Diagnostic/Logging.h>

#include <spdlog/sinks/stdout_sinks.h>
#include <spdlog/logger.h>

#include <atomic>
#include <cstdlib>
#include <cstdio>
#include <memory>
#include <mutex>

namespace universaldevkit::diagnostic {
    namespace details {
        struct State {
            std::mutex mutex;
            std::shared_ptr<spdlog::logger> logger;
            std::atomic<Level> minimumLevel{ Level::Info };
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

        std::shared_ptr<spdlog::logger> GetLogger() {
            auto& state = details::GetState();
            std::scoped_lock lock{ state.mutex };
            return state.logger;
        }

        void EmergencyWrite(std::string_view message) noexcept {
            // No allocation, callbacks or recursive logging in the fallback.
            std::fwrite(message.data(), 1, message.size(), stderr);
            std::fputc('\n', stderr);
            std::fflush(stderr);
        }
    } // namespace details

    bool Logger::Initialize(const Options& options) noexcept {
        try {
            auto& state = details::GetState();
            std::scoped_lock lock{ state.mutex };
            if (state.logger) {
                return false;
            }

            auto sink = std::make_shared<spdlog::sinks::stderr_sink_mt>();
            auto logger = std::make_shared<spdlog::logger>("Diagnostic", std::move(sink));
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
            state.minimumLevel.store(options.minimumLevel, std::memory_order_relaxed);
            state.logger = std::move(logger);
            return true;
        }
        catch (...) {
            details::EmergencyWrite("Diagnostic: initialization failed");
            return false;
        }
    }

    void Logger::Shutdown() noexcept {
        try {
            std::shared_ptr<spdlog::logger> logger;
            {
                auto& state = details::GetState();
                std::scoped_lock lock{ state.mutex };
                logger = std::move(state.logger);
            }
            if (logger) {
                logger->flush();
            }
        }
        catch (...) {
            details::EmergencyWrite("Diagnostic: shutdown failed");
        }
    }

    void Logger::Flush() noexcept {
        try {
            if (auto logger = details::GetLogger()) {
                logger->flush();
            }
        }
        catch (...) {
            details::EmergencyWrite("Diagnostic: flush failed");
        }
    }

    void Logger::SetLevel(Level level) noexcept {
        try {
            details::GetState().minimumLevel.store(level, std::memory_order_relaxed);
        }
        catch (...) {
            details::EmergencyWrite("Diagnostic: level update failed");
        }
    }

    bool Logger::ShouldLog(Level level) noexcept {
        try {
            return level >= details::GetState().minimumLevel.load(std::memory_order_relaxed) && level < Level::Off;
        }
        catch (...) {
            return false;
        }
    }

    void Logger::Write(Level level, std::string_view category, std::string_view message, std::source_location sourceLocation) noexcept {
        if (!Logger::ShouldLog(level)) {
            return;
        }
        try {
            if (auto logger = details::GetLogger()) {
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