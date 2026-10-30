#include <UniversalDevKit/Platform.h>

#if UNIVERSALDEVKIT_PLATFORM_ANDROID
#include "../../PlatformBackend.h"

namespace universaldevkit::diagnostic {
    bool PlatformBackend::SupportsPackageDirectories() noexcept {
        return false;
    }

    std::shared_ptr<spdlog::sinks::sink> PlatformBackend::CreateDebuggerSink() {
        return {};
    }
}
#endif