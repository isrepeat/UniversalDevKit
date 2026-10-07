cmake_minimum_required(VERSION 3.22)

if(CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
    file(TO_CMAKE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/!artifacts/" artifacts_prefix)
    file(TO_CMAKE_PATH "${CMAKE_BINARY_DIR}/" binary_prefix)
    string(FIND "${binary_prefix}" "${artifacts_prefix}" artifacts_position)
    if(NOT artifacts_position EQUAL 0)
        message(FATAL_ERROR "Configure UniversalDevKit inside !artifacts: use a preset or -B !artifacts/<platform>/cmake/<project>")
    endif()
endif()

project(UniversalDevKit VERSION 0.1.0 LANGUAGES CXX)

add_library(universaldevkit_headers INTERFACE)
add_library(UniversalDevKit::Headers ALIAS universaldevkit_headers)

target_include_directories(universaldevkit_headers INTERFACE
    "$<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/Includes>"
    "$<INSTALL_INTERFACE:include>"
)
target_compile_features(universaldevkit_headers INTERFACE cxx_std_17)

add_library(universaldevkit_helpers STATIC Sources/Helpers/Math.cpp)
add_library(UniversalDevKit::Helpers ALIAS universaldevkit_helpers)
target_link_libraries(universaldevkit_helpers PUBLIC UniversalDevKit::Headers)
set_target_properties(universaldevkit_helpers PROPERTIES
    EXPORT_NAME Helpers.Static
    POSITION_INDEPENDENT_CODE ON
)

include(GNUInstallDirs)
add_library(universaldevkit_diagnostic STATIC Sources/Diagnostic/Logging.cpp)
add_library(UniversalDevKit::Diagnostic ALIAS universaldevkit_diagnostic)
target_link_libraries(universaldevkit_diagnostic PUBLIC UniversalDevKit::Headers)
set_target_properties(universaldevkit_diagnostic PROPERTIES EXPORT_NAME Diagnostic.Static POSITION_INDEPENDENT_CODE ON)
include(CMakePackageConfigHelpers)

foreach(component IN ITEMS Helpers Diagnostic)
    string(TOLOWER "${component}" component_lower)
    string(TOUPPER "${component}" component_upper)
    get_target_property(component_source universaldevkit_${component_lower} SOURCES)
    add_library(universaldevkit_${component_lower}_dynamic SHARED ${component_source})
    add_library(UniversalDevKit::${component}.Static ALIAS universaldevkit_${component_lower})
    add_library(UniversalDevKit::${component}.Dynamic ALIAS universaldevkit_${component_lower}_dynamic)
    target_link_libraries(universaldevkit_${component_lower}_dynamic PUBLIC UniversalDevKit::Headers)
    target_compile_definitions(universaldevkit_${component_lower}_dynamic
        PUBLIC UNIVERSALDEVKIT_${component_upper}_DYNAMIC
        PRIVATE UNIVERSALDEVKIT_${component_upper}_EXPORTS
    )
    set_target_properties(universaldevkit_${component_lower}_dynamic PROPERTIES EXPORT_NAME ${component}.Dynamic)
endforeach()

set_target_properties(universaldevkit_headers PROPERTIES EXPORT_NAME Headers)
install(TARGETS universaldevkit_headers universaldevkit_helpers universaldevkit_diagnostic
    universaldevkit_helpers_dynamic universaldevkit_diagnostic_dynamic EXPORT UniversalDevKitTargets
    ARCHIVE DESTINATION "${CMAKE_INSTALL_LIBDIR}"
    LIBRARY DESTINATION "${CMAKE_INSTALL_LIBDIR}"
    RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}"
)
install(DIRECTORY Includes/ DESTINATION include)
install(EXPORT UniversalDevKitTargets
    NAMESPACE UniversalDevKit::
    DESTINATION "${CMAKE_INSTALL_LIBDIR}/cmake/UniversalDevKit"
)
configure_package_config_file(
    Projects/Cmake/UniversalDevKitConfig.cmake.in
    "${CMAKE_CURRENT_BINARY_DIR}/UniversalDevKitConfig.cmake"
    INSTALL_DESTINATION "${CMAKE_INSTALL_LIBDIR}/cmake/UniversalDevKit"
)
write_basic_package_version_file(
    "${CMAKE_CURRENT_BINARY_DIR}/UniversalDevKitConfigVersion.cmake"
    COMPATIBILITY SameMajorVersion
    ARCH_INDEPENDENT
)
install(FILES
    "${CMAKE_CURRENT_BINARY_DIR}/UniversalDevKitConfig.cmake"
    "${CMAKE_CURRENT_BINARY_DIR}/UniversalDevKitConfigVersion.cmake"
    DESTINATION "${CMAKE_INSTALL_LIBDIR}/cmake/UniversalDevKit"
)