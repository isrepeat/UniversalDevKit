#include <spdlog/sinks/rotating_file_sink.h>
#include <spdlog/logger.h>

#include "LoggingBackend.h"
#include "Logging.h"

#include <utility>
#include <vector>
#include <memory>
#include <mutex>

namespace utility_helpers::logging::_details {
    constexpr std::string_view sessionSeparator = "==========================================================================================================";
    std::mutex mutex;
    Options options;
    std::shared_ptr<spdlog::logger> logger;

    spdlog::level::level_enum ToSpdlogLevel(Level level) {
        switch (level) {
        case Level::trace:
            return spdlog::level::trace;
        case Level::debug:
            return spdlog::level::debug;
        case Level::info:
            return spdlog::level::info;
        case Level::warning:
            return spdlog::level::warn;
        case Level::error:
            return spdlog::level::err;
        }
        return spdlog::level::info;
    }
}

namespace utility_helpers::logging {
    void Configure(Options newOptions) {
        std::lock_guard lock(_details::mutex);
        if (_details::logger == nullptr) {
            _details::options = std::move(newOptions);
        }
    }

    void Initialize(std::string_view applicationName) {
        std::lock_guard lock(_details::mutex);
        if (_details::logger != nullptr) {
            return;
        }
        std::vector<spdlog::sink_ptr> sinks;
        sinks.push_back(_details::CreatePlatformSink(applicationName));
        if (!_details::options.filePath.empty()) {
            sinks.push_back(std::make_shared<spdlog::sinks::rotating_file_sink_mt>(
                _details::options.filePath.string(),
                _details::options.maxFileSize,
                _details::options.maxFiles));
        }
        _details::logger = std::make_shared<spdlog::logger>(
            "utility_helpers",
            sinks.begin(),
            sinks.end());
        _details::logger->set_pattern("[%L] [%n] [%t] %d.%m.%Y %H:%M:%S.%e {%s:%# %!} %v");
        _details::logger->set_level(_details::options.verbose ? spdlog::level::trace : spdlog::level::info);
        _details::logger->flush_on(spdlog::level::trace);
        if (_details::options.appendNewSession) {
            _details::logger->debug("");
            _details::logger->debug(_details::sessionSeparator);
            _details::logger->debug("                       New session started");
            _details::logger->debug(_details::sessionSeparator);
        }
    }

    void Flush() {
        Initialize("UtilityHelpers");
        _details::logger->flush();
    }

    void Write(
        Level level,
        std::string_view category,
        std::string_view message,
        const char* file,
        int line,
        const char* function) {
        Initialize("UtilityHelpers");
        _details::logger->log(
            {file, line, function},
            _details::ToSpdlogLevel(level),
            "[{}] {}",
            category,
            message);
    }

    Scope::Scope(
        std::string_view category,
        std::string name,
        const char* file,
        int line,
        const char* function)
        : category(category)
        , name(std::move(name))
        , file(file)
        , line(line)
        , function(function) {
        Write(Level::debug, this->category, ">> " + this->name, this->file, this->line, this->function);
    }

    Scope::~Scope() {
        Write(Level::debug, this->category, "<< " + this->name, this->file, this->line, this->function);
    }
}