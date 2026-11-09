# Восстанавливаем закреплённый пакет также при конфигурации напрямую из IDE.
find_program(android_build_tools_powershell NAMES powershell.exe REQUIRED)
execute_process(
    COMMAND "${android_build_tools_powershell}" -NoProfile -ExecutionPolicy Bypass
        -File "${CMAKE_CURRENT_LIST_DIR}/../build.ps1" -Command restore
    RESULT_VARIABLE android_build_tools_result
    OUTPUT_VARIABLE android_build_tools_output
    ERROR_VARIABLE android_build_tools_error
    OUTPUT_STRIP_TRAILING_WHITESPACE
)
if(NOT android_build_tools_result EQUAL 0)
    message(FATAL_ERROR "AndroidBuildTools restore failed: ${android_build_tools_output}\n${android_build_tools_error}")
endif()
# NuGet выводит журнал восстановления; последняя строка всегда содержит путь пакета.
string(REGEX MATCH "[^\r\n]+$" android_build_tools_root "${android_build_tools_output}")
file(TO_CMAKE_PATH "${android_build_tools_root}" android_build_tools_root)
set(ANDROID_BUILD_TOOLS_ROOT "${android_build_tools_root}" CACHE INTERNAL "Restored AndroidBuildTools package root")
include("${ANDROID_BUILD_TOOLS_ROOT}/cmake/AndroidToolchain.cmake")