#include "Internal/Bridge/Diagnostic.h"

namespace universaldevkit::windows::androidapppreviewerpluginsdk::internal::bridge {
    std::string& LastError() {
        static thread_local std::string lastError;
        return lastError;
    }
}