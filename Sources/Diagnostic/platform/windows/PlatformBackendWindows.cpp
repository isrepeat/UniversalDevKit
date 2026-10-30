#include <UniversalDevKit/Platform.h>

#if UNIVERSALDEVKIT_PLATFORM_WINDOWS
#include "../../PlatformBackend.h"

#include <spdlog/sinks/msvc_sink.h>

namespace universaldevkit::diagnostic {
    bool PlatformBackend::SupportsPackageDirectories() noexcept {
        return true;
    }

    std::shared_ptr<spdlog::sinks::sink> PlatformBackend::CreateDebuggerSink() {
        return std::make_shared<spdlog::sinks::msvc_sink_mt>();
    }
}
#endif