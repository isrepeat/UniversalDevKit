#include <UniversalDevKit/Diagnostic/Logging.h>

#include <iostream>
#include <mutex>

namespace universaldevkit::diagnostic {
    void Log(std::string_view message) {
        static std::mutex outputMutex;
        const std::lock_guard<std::mutex> lock(outputMutex);
        std::clog << message << '\n';
    }
}