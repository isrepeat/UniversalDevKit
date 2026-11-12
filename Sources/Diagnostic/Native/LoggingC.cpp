#include "../../../Includes/Diagnostic/UniversalDevKit/Diagnostic/LoggingC.h"

#include "LogRecord.h"

#include <filesystem>
#include <cstdlib>
#include <cstring>
#include <cstddef>
#include <limits>

namespace diagnostic = universaldevkit::diagnostic;

int32_t UdkDiagnosticInitialize(
    uint32_t loggerId,
    const UdkDiagnosticOptions* options,
    const char* filePath,
    int32_t* systemError,
    char** message
) {
    if (systemError != nullptr) {
        *systemError = 0;
    }
    if (message != nullptr) {
        *message = nullptr;
    }
    if (options == nullptr || systemError == nullptr || message == nullptr ||
        options->maxFileSize > std::numeric_limits<std::size_t>::max() ||
        options->maxFiles > std::numeric_limits<std::size_t>::max()) {
        return static_cast<int32_t>(diagnostic::LoggerInitError::InvalidOptions);
    }

    try {
        diagnostic::LoggerOptions loggerOptions;
        loggerOptions.minimumLevel = static_cast<diagnostic::Level>(options->minimumLevel);
        if (filePath != nullptr) {
            const auto utf8Path = reinterpret_cast<const char8_t*>(filePath);
            loggerOptions.filePath = std::filesystem::path(utf8Path);
        }
        loggerOptions.logFolder = static_cast<diagnostic::LogFolder>(options->logFolder);
        loggerOptions.fileMode = static_cast<diagnostic::FileMode>(options->fileMode);
        loggerOptions.maxFileSize = static_cast<std::size_t>(options->maxFileSize);
        loggerOptions.maxFiles = static_cast<std::size_t>(options->maxFiles);
        loggerOptions.appendNewSession = (options->flags & UdkDiagnosticAppendNewSession) != 0;
        loggerOptions.enableConsole = (options->flags & UdkDiagnosticEnableConsole) != 0;
        loggerOptions.enableDebugger = (options->flags & UdkDiagnosticEnableDebugger) != 0;
        loggerOptions.colorConsole = (options->flags & UdkDiagnosticColorConsole) != 0;

        const auto result = diagnostic::Logger::Initialize(loggerOptions, loggerId);
        *systemError = result.systemError.value();
        if (!result.message.empty()) {
            const auto size = result.message.size() + 1;
            *message = static_cast<char*>(std::malloc(size));
            if (*message != nullptr) {
                std::memcpy(*message, result.message.c_str(), size);
            }
        }
        return static_cast<int32_t>(result.error);
    }
    catch (...) {
        return static_cast<int32_t>(diagnostic::LoggerInitError::InitializationFailed);
    }
}

void UdkDiagnosticFreeMessage(char* message) {
    std::free(message);
}

void UdkDiagnosticWriteRecord(
    uint32_t loggerId,
    int32_t level,
    const char* category,
    const char* message,
    const char* file,
    const char* member,
    int32_t line
) {
    diagnostic::details::WriteRecord(
        static_cast<diagnostic::Level>(level),
        category != nullptr ? category : "",
        message != nullptr ? message : "",
        { file != nullptr ? file : "", line, member != nullptr ? member : "" },
        loggerId
    );
}

void UdkDiagnosticFlush(uint32_t loggerId) {
    diagnostic::Logger::Flush(loggerId);
}

void UdkDiagnosticShutdownLoggers() {
    diagnostic::Logger::Shutdown();
}