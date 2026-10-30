#pragma once

#include <string_view>
#include <memory>

namespace spdlog::sinks {
    class sink;
}

namespace utility_helpers::logging::_details {
    std::shared_ptr<spdlog::sinks::sink> CreatePlatformSink(std::string_view applicationName);
}