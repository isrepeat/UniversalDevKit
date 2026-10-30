#pragma once
#include "Export.h"

#include <string_view>

// Сохраняем прежнее имя публичного макроса для исходной совместимости.
#define UNIVERSALDEVKIT_TEXT_API UNIVERSALDEVKIT_HELEPRSTEST_API

namespace universaldevkit::heleprstest::text {
    // Синхронно читает действительный неизменный буфер, не сохраняет и не освобождает его.
    // Пустой текст возвращает false; проверяются только последние байты CR или LF.
    UNIVERSALDEVKIT_HELEPRSTEST_API bool EndsWithLineBreak(std::string_view text) noexcept;
}