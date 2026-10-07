cmake_minimum_required(VERSION 3.22)

project(UniversalDevKit VERSION 0.1.0 LANGUAGES CXX)

add_library(universaldevkit_headers INTERFACE)
add_library(UniversalDevKit::Headers ALIAS universaldevkit_headers)

target_include_directories(universaldevkit_headers INTERFACE
    "$<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>"
    "$<INSTALL_INTERFACE:include>"
)
target_compile_features(universaldevkit_headers INTERFACE cxx_std_17)

include(GNUInstallDirs)
include(CMakePackageConfigHelpers)

set_target_properties(universaldevkit_headers PROPERTIES EXPORT_NAME Headers)
install(TARGETS universaldevkit_headers EXPORT UniversalDevKitTargets)
install(DIRECTORY include/ DESTINATION include)
install(EXPORT UniversalDevKitTargets
    NAMESPACE UniversalDevKit::
    DESTINATION "${CMAKE_INSTALL_LIBDIR}/cmake/UniversalDevKit"
)
configure_package_config_file(
    cmake/UniversalDevKitConfig.cmake.in
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