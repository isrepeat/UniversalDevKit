#include <UniversalDevKit/Platform.h>

#if UNIVERSALDEVKIT_PLATFORM_WINDOWS
#include "../../PlatformBackend.h"

#include <spdlog/sinks/msvc_sink.h>

#include "UniversalDevKit/Diagnostic/Logging.h"

namespace universaldevkit::diagnostic {
    bool PlatformBackend::SupportsPackageDirectories() noexcept {
        return true;
    }

    std::shared_ptr<spdlog::sinks::sink> PlatformBackend::CreateDebuggerSink() {
        return std::make_shared<spdlog::sinks::msvc_sink_mt>();
    }
}

#if defined(UNIVERSALDEVKIT_DIAGNOSTIC_EXPORTS)
extern "C" __declspec(dllexport) int UdkDiagnosticInitializeFile(const wchar_t* path) noexcept {
    try {
        universaldevkit::diagnostic::LoggerOptions loggerOptions;
        loggerOptions.filePath = path;
        return universaldevkit::diagnostic::Logger::Initialize(loggerOptions) ? 1 : 0;
    } catch (...) {
        return 0;
    }
}

extern "C" __declspec(dllexport) void UdkDiagnosticWrite(int isError, const wchar_t* message) noexcept {
    using namespace universaldevkit::diagnostic;
    Logger::Write(isError ? Level::Error : Level::Info, "UdkCli.Setup", std::wstring_view(message));
    Logger::Flush();
}

extern "C" __declspec(dllexport) void UdkDiagnosticShutdown() noexcept {
    universaldevkit::diagnostic::Logger::Shutdown();
}
#endif // defined(UNIVERSALDEVKIT_DIAGNOSTIC_EXPORTS)
#endif // UNIVERSALDEVKIT_PLATFORM_WINDOWS