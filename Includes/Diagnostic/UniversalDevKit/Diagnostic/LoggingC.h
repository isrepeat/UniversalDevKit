#pragma once
#include "Export.h"

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct UdkDiagnosticOptions {
    uint64_t maxFileSize;
    uint64_t maxFiles;
    int32_t minimumLevel;
    int32_t logFolder;
    int32_t fileMode;
    uint32_t flags;
} UdkDiagnosticOptions;

enum {
    UdkDiagnosticAppendNewSession = 1,
    UdkDiagnosticEnableConsole = 2,
    UdkDiagnosticEnableDebugger = 4,
    UdkDiagnosticColorConsole = 8
};

// Strings are NUL-terminated UTF-8. Enum values follow the Diagnostic logger contract.
// Both output pointers are required. Release a returned message with UdkDiagnosticFreeMessage.
UNIVERSALDEVKIT_DIAGNOSTIC_API int32_t UdkDiagnosticInitialize(
    uint32_t loggerId,
    const UdkDiagnosticOptions* options,
    const char* filePath,
    int32_t* systemError,
    char** message
);
UNIVERSALDEVKIT_DIAGNOSTIC_API void UdkDiagnosticFreeMessage(char* message);
UNIVERSALDEVKIT_DIAGNOSTIC_API void UdkDiagnosticWriteRecord(
    uint32_t loggerId,
    int32_t level,
    const char* category,
    const char* message,
    const char* file,
    const char* member,
    int32_t line
);
UNIVERSALDEVKIT_DIAGNOSTIC_API void UdkDiagnosticFlush(uint32_t loggerId);
UNIVERSALDEVKIT_DIAGNOSTIC_API void UdkDiagnosticShutdownLoggers(void);

#ifdef __cplusplus
}
#endif