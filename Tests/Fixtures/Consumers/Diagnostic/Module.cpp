#include <UniversalDevKit/Diagnostic/Logging.h>

#if defined(_WIN32)
#define DIAGNOSTIC_TEST_API __declspec(dllexport)
#else
#define DIAGNOSTIC_TEST_API __attribute__((visibility("default")))
#endif

extern "C" DIAGNOSTIC_TEST_API bool MODULE_INITIALIZE(universaldevkit::diagnostic::LoggerId loggerId, const char* path) {
    universaldevkit::diagnostic::LoggerOptions loggerOptions;
    loggerOptions.filePath = std::filesystem::u8path(path);
    loggerOptions.minimumLevel = universaldevkit::diagnostic::Level::Debug;
    return static_cast<bool>(universaldevkit::diagnostic::Logger::Initialize(loggerOptions, loggerId));
}

extern "C" DIAGNOSTIC_TEST_API void MODULE_WRITE(universaldevkit::diagnostic::LoggerId loggerId, const char* message) {
    UDK_LOG_WARNING_N(loggerId, "Module", "{}", message);
}

extern "C" DIAGNOSTIC_TEST_API bool MODULE_ENABLED(universaldevkit::diagnostic::LoggerId loggerId) {
    return universaldevkit::diagnostic::Logger::ShouldLog(universaldevkit::diagnostic::Level::Debug, loggerId);
}

extern "C" DIAGNOSTIC_TEST_API void MODULE_SET_LEVEL(universaldevkit::diagnostic::LoggerId loggerId) {
    universaldevkit::diagnostic::Logger::SetLevel(universaldevkit::diagnostic::Level::Warning, loggerId);
}