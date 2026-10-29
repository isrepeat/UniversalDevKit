cmake_minimum_required(VERSION 3.22)
project(DiagnosticContract LANGUAGES CXX)

set(UniversalDevKit_COMPONENTS Diagnostic CACHE STRING "" FORCE)
set(UniversalDevKit_BUILD_STATIC OFF CACHE BOOL "" FORCE)
set(UniversalDevKit_INSTALL OFF CACHE BOOL "" FORCE)
get_filename_component(udkRoot "${CMAKE_CURRENT_SOURCE_DIR}/../../../.." ABSOLUTE)
add_subdirectory("${udkRoot}" udk)
find_package(Threads REQUIRED)

# Modules are independently compiled consumers of the same Diagnostic DLL/SO.
foreach(module A B)
    add_library(DiagnosticModule${module} SHARED Module.cpp)
    target_link_libraries(DiagnosticModule${module} PRIVATE UniversalDevKit::Diagnostic.Dynamic)
    target_compile_definitions(DiagnosticModule${module} PRIVATE
        MODULE_INITIALIZE=Module${module}Initialize MODULE_WRITE=Module${module}Write
        MODULE_ENABLED=Module${module}Enabled MODULE_SET_LEVEL=Module${module}SetLevel)
    set_target_properties(DiagnosticModule${module} PROPERTIES CXX_VISIBILITY_PRESET hidden VISIBILITY_INLINES_HIDDEN ON)
endforeach()

add_executable(DiagnosticContract Main.cpp)
target_link_libraries(DiagnosticContract PRIVATE
    UniversalDevKit::Diagnostic.Dynamic DiagnosticModuleA DiagnosticModuleB Threads::Threads)
foreach(target DiagnosticContract DiagnosticModuleA DiagnosticModuleB)
    target_compile_features(${target} PRIVATE cxx_std_20)
    if(MSVC)
        target_compile_options(${target} PRIVATE /utf-8 /EHsc)
    endif()
endforeach()

# Keep a self-contained runtime directory for both CTest and adb deployment.
foreach(target universaldevkit_diagnostic_dynamic DiagnosticModuleA DiagnosticModuleB DiagnosticContract)
    set_target_properties(${target} PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin/$<CONFIG>"
        LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin/$<CONFIG>"
        BUILD_RPATH "$ORIGIN")
endforeach()

enable_testing()
foreach(test contract threads modules)
    add_test(NAME Diagnostic.${test} COMMAND DiagnosticContract "${test}" "${CMAKE_BINARY_DIR}/results/$<CONFIG>/${test}")
    set_tests_properties(Diagnostic.${test} PROPERTIES TIMEOUT 180)
endforeach()