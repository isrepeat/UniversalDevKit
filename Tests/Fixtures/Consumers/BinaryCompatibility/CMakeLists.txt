cmake_minimum_required(VERSION 3.22)
project(BinaryCompatibility LANGUAGES CXX)
if(TEST_COMPILER_VERSION)
    # Проверяем отказ политики метаданных, не имитируя сборку другим компилятором.
    set(CMAKE_CXX_COMPILER_VERSION "${TEST_COMPILER_VERSION}")
endif()
if(TEST_TOOLSET)
    set(CMAKE_VS_PLATFORM_TOOLSET "${TEST_TOOLSET}")
endif()
if(TEST_ARCHITECTURE)
    set(CMAKE_CXX_COMPILER_ARCHITECTURE_ID "${TEST_ARCHITECTURE}")
endif()
find_package(UniversalDevKit CONFIG REQUIRED COMPONENTS Diagnostic)
add_executable(consumer Main.cpp)
target_link_libraries(consumer PRIVATE UniversalDevKit::Diagnostic.${TEST_VARIANT})
if(TEST_RUNTIME)
    set_property(TARGET consumer PROPERTY MSVC_RUNTIME_LIBRARY "${TEST_RUNTIME}")
endif()
if(DEFINED TEST_ITERATOR_ABI)
    target_compile_definitions(consumer PRIVATE _ITERATOR_DEBUG_LEVEL=${TEST_ITERATOR_ABI})
endif()
if(TEST_VARIANT STREQUAL "Dynamic")
    add_custom_command(TARGET consumer POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            $<TARGET_RUNTIME_DLLS:consumer> $<TARGET_FILE_DIR:consumer>
        COMMAND_EXPAND_LISTS
    )
endif()