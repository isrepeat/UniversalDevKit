#include <UniversalDevKit/DiagnosticTest/Logging.h>

#include <UniversalDevKit/HeleprsTest/Text.h>

#include <iostream>
#include <mutex>

namespace universaldevkit::diagnostictest {
    void Log(std::string_view message) noexcept {
        static_cast<void>(TryLog(message));
    }

    bool TryLog(std::string_view message) noexcept {
        try {
            // 1. Сериализуем запись в пределах текущей реализации DiagnosticTest.
            static std::mutex outputMutex;
            const std::lock_guard<std::mutex> lock(outputMutex);

            // 2. Добавляем перевод строки только если сообщение ещё не завершено им.
            std::clog << message;
            if (!universaldevkit::heleprstest::text::EndsWithLineBreak(message)) {
                std::clog << '\n';
            }
            return std::clog.good();
        }
        catch (...) {
            // Ошибка диагностики не должна прерывать основной код приложения.
            return false;
        }
    }
}