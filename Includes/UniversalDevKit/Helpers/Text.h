#pragma once
#include "Export.h"

#include <string_view>

// Сохраняем прежнее имя публичного макроса для исходной совместимости.
#define UNIVERSALDEVKIT_TEXT_API UNIVERSALDEVKIT_HELPERS_API

namespace universaldevkit::text {
    // Синхронно читает действительный неизменный буфер, не сохраняет и не освобождает его.
    // Пустой текст возвращает false; проверяются только последние байты CR или LF.
    UNIVERSALDEVKIT_HELPERS_API bool EndsWithLineBreak(std::string_view text) noexcept;
}