include_guard(GLOBAL)

# Общие исходники собираются тем же toolchain, что и приложение.
if (NOT TARGET AndroidApplication::Framework)
    add_subdirectory(
        "${CMAKE_CURRENT_LIST_DIR}/../build/native/AndroidBuildTools/ApplicationFramework"
        "${CMAKE_BINARY_DIR}/AndroidApplicationFramework"
    )
endif()