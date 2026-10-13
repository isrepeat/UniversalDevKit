# Тестовый host-инструмент: преобразует число в публичную функцию.
if(NOT DEFINED OUTPUT_ROOT OR NOT EXISTS "${INPUT_FILE}")
    message(FATAL_ERROR "Generator requires OUTPUT_ROOT and an existing INPUT_FILE")
endif()
file(READ "${INPUT_FILE}" value)
string(STRIP "${value}" value)
if(NOT value MATCHES "^[0-9]+$")
    message(FATAL_ERROR "Expected a nonnegative integer")
endif()
file(MAKE_DIRECTORY "${OUTPUT_ROOT}/Includes/UniversalDevKit/GeneratedProbe/Generated" "${OUTPUT_ROOT}/Sources")
file(WRITE "${OUTPUT_ROOT}/Includes/UniversalDevKit/GeneratedProbe/Generated/Value.h"
    "// Сгенерировано Generate.cmake. Изменяйте Input.txt.\n#pragma once\n#include <UniversalDevKit/GeneratedProbe/Export.h>\n\nUNIVERSALDEVKIT_GENERATEDPROBE_API int GeneratedValue() noexcept;")
file(WRITE "${OUTPUT_ROOT}/Sources/Value.cpp"
    "// Сгенерировано Generate.cmake. Изменяйте Input.txt.\n#include <UniversalDevKit/GeneratedProbe/Generated/Value.h>\n\nint GeneratedValue() noexcept { return ${value}; }")