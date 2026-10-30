#if defined(__ANDROID__)
#include <spdlog/sinks/android_sink.h>

#include "../../LoggingBackend.h"

#include <string>

namespace utility_helpers::logging::_details {
    std::shared_ptr<spdlog::sinks::sink> CreatePlatformSink(std::string_view applicationName) {
        return std::make_shared<spdlog::sinks::android_sink_mt>(std::string(applicationName));
    }
}
#endif