cmake_minimum_required(VERSION 3.22)
project(RequirementsPackage LANGUAGES CXX)
find_package(UniversalDevKit 0.1 CONFIG REQUIRED COMPONENTS Example)
add_executable(requirements_consumer Main.cpp)
set_property(TARGET requirements_consumer PROPERTY CXX_STANDARD 17)
target_link_libraries(requirements_consumer PRIVATE UniversalDevKit::Example.Static)
if(WIN32)
    add_custom_command(TARGET requirements_consumer POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            $<TARGET_RUNTIME_DLLS:requirements_consumer> $<TARGET_FILE_DIR:requirements_consumer>
        COMMAND_EXPAND_LISTS
    )
endif()

enable_testing()
add_test(NAME Requirements COMMAND requirements_consumer)