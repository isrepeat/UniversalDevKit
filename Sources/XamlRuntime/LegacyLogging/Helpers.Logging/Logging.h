#pragma once

#include <spdlog/fmt/fmt.h>

#include <string_view>
#include <filesystem>
#include <cstddef>
#include <string>

namespace utility_helpers::logging {
    enum class Level {
        trace,
        debug,
        info,
        warning,
        error,
    };

    struct Options {
        static constexpr std::size_t defaultMaxFileSize = 2 * 1024 * 1024;
        static constexpr std::size_t defaultMaxFiles = 3;

        std::filesystem::path filePath;
        bool verbose = true;
        std::size_t maxFileSize = defaultMaxFileSize;
        std::size_t maxFiles = defaultMaxFiles;
        bool appendNewSession = true;
    };

    class Scope final {
    public:
        Scope(
            std::string_view category,
            std::string name,
            const char* file,
            int line,
            const char* function);
        ~Scope();

        Scope(const Scope&) = delete;
        Scope& operator=(const Scope&) = delete;

    private:
        std::string category;
        std::string name;
        const char* file = nullptr;
        int line = 0;
        const char* function = nullptr;
    };

    void Configure(Options options);
    void Initialize(std::string_view applicationName);
    void Flush();
    void Write(
        Level level,
        std::string_view category,
        std::string_view message,
        const char* file,
        int line,
        const char* function);
}

#define LOG(level, category, ...) \
    ::utility_helpers::logging::Write( \
        ::utility_helpers::logging::Level::level, \
        category, \
        fmt::format(__VA_ARGS__), \
        __FILE__, \
        __LINE__, \
        __func__)

#define LOG_TRACE(category, ...) LOG(trace, category, __VA_ARGS__)
#define LOG_DEBUG(category, ...) LOG(debug, category, __VA_ARGS__)
#define LOG_INFO(category, ...) LOG(info, category, __VA_ARGS__)
#define LOG_WARNING(category, ...) LOG(warning, category, __VA_ARGS__)
#define LOG_ERROR(category, ...) LOG(error, category, __VA_ARGS__)

#define UTILITY_HELPERS_LOG_CONCAT_INNER(left, right) left##right
#define UTILITY_HELPERS_LOG_CONCAT(left, right) \
    UTILITY_HELPERS_LOG_CONCAT_INNER(left, right)

#define LOG_FUNCTION_SCOPE(category, ...) \
    ::utility_helpers::logging::Scope \
        UTILITY_HELPERS_LOG_CONCAT(logScope_, __COUNTER__)( \
            category, \
            fmt::format(__VA_ARGS__), \
            __FILE__, \
            __LINE__, \
            __func__)