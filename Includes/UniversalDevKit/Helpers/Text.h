#pragma once
#include "Export.h"

#include <string_view>

// Сохраняем прежнее имя публичного макроса для исходной совместимости.
#define UNIVERSALDEVKIT_TEXT_API UNIVERSALDEVKIT_HELPERS_API

namespace universaldevkit::text {
    UNIVERSALDEVKIT_HELPERS_API bool EndsWithLineBreak(std::string_view text) noexcept;
}