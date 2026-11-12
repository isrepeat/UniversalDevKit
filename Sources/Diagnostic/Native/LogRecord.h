#pragma once
#include <UniversalDevKit/Diagnostic/Logging.h>

namespace universaldevkit::diagnostic::details {
    struct SourceLocation {
        const char* file;
        int line;
        const char* member;
    };

    void WriteRecord(
        Level level,
        std::string_view category,
        std::string_view message,
        SourceLocation sourceLocation,
        LoggerId loggerId
    ) noexcept;
}