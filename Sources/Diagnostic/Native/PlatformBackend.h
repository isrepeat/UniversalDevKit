#pragma once
#include <spdlog/sinks/sink.h>

#include <memory>

namespace universaldevkit::diagnostic {
    // Internal platform boundary; spdlog types never enter the public API.
    class PlatformBackend final {
    public:
        PlatformBackend() = delete;

        static bool SupportsPackageDirectories() noexcept;
        static std::shared_ptr<spdlog::sinks::sink> CreateDebuggerSink();
    };
}