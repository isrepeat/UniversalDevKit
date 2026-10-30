#if defined(_WIN32)
#include <spdlog/sinks/msvc_sink.h>

#include "../../LoggingBackend.h"

#include <string>

namespace utility_helpers::logging::_details {
    std::shared_ptr<spdlog::sinks::sink> CreatePlatformSink(std::string_view) {
        return std::make_shared<spdlog::sinks::msvc_sink_mt>();
    }
}
#endif