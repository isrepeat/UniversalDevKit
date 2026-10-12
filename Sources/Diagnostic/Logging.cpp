#include "../../Includes/UniversalDevKit/Diagnostic/Logging.h"

#include "../../Includes/UniversalDevKit/Helpers/Text.h"

#include <iostream>
#include <mutex>

namespace universaldevkit::diagnostic {
    void Log(std::string_view message) {
        static std::mutex outputMutex;
        const std::lock_guard<std::mutex> lock(outputMutex);
        // Добавляем перевод строки только если сообщение ещё не завершено им.
        std::clog << message;
        if (!universaldevkit::text::EndsWithLineBreak(message)) {
            std::clog << '\n';
        }
    }
}