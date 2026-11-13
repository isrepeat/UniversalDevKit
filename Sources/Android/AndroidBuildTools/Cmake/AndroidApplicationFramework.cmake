include_guard(GLOBAL)

# Build shared sources with the same toolchain as the application.
if (NOT TARGET AndroidApplication::Framework)
    add_subdirectory(
        "${CMAKE_CURRENT_LIST_DIR}/../build/native/Android/AndroidBuildTools/ApplicationFramework"
        "${CMAKE_BINARY_DIR}/AndroidApplicationFramework"
    )
endif()