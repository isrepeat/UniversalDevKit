cmake_minimum_required(VERSION 3.22)
project(UniversalDevKitPackageConsumer LANGUAGES CXX)
set(UDK_TEST_COMPONENT Diagnostic CACHE STRING "Requested component")
find_package(UniversalDevKit 0.1 CONFIG REQUIRED COMPONENTS ${UDK_TEST_COMPONENT})
foreach(mode IN ITEMS Static Dynamic)
    add_executable(consumer_${mode} Main.cpp)
    target_link_libraries(consumer_${mode} PRIVATE UniversalDevKit::Diagnostic.${mode})
    if(WIN32 AND mode STREQUAL "Dynamic")
        add_custom_command(TARGET consumer_${mode} POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                $<TARGET_RUNTIME_DLLS:consumer_${mode}> $<TARGET_FILE_DIR:consumer_${mode}>
            COMMAND_EXPAND_LISTS
        )
    endif()
endforeach()

enable_testing()
add_test(NAME Static COMMAND consumer_Static)
add_test(NAME Dynamic COMMAND consumer_Dynamic)