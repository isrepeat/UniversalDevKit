#pragma once
#include "Export.h"

#include <string_view>

namespace universaldevkit::diagnostictest {
    // Читает буфер синхронно, не сохраняет и не освобождает его. Буфер должен быть
    // действителен и неизменен до возвращения. Ошибки подавляются, исключения не выходят.
    // Вызовы сериализованы внутри одной реализации DiagnosticTest; повторный вход запрещён.
    // Общая блокировка разных DLL и немедленная доставка/сброс вывода не гарантируются.
    UNIVERSALDEVKIT_DIAGNOSTICTEST_API void Log(std::string_view message) noexcept;

    // Тот же контракт буфера и потоков. Возвращает false при ошибке блокировки/вывода.
    // Запись может быть частичной; состояние ошибки std::clog не сбрасывается.
    // true означает успех операций потока, но не гарантирует сохранение данных на диске.
    UNIVERSALDEVKIT_DIAGNOSTICTEST_API bool TryLog(std::string_view message) noexcept;
}