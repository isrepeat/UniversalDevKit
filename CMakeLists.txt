cmake_minimum_required(VERSION 3.22)

# Ограничение каталога сборки действует только при самостоятельной сборке репозитория.
if(CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
    file(TO_CMAKE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/!artifacts/" artifacts_prefix)
    file(TO_CMAKE_PATH "${CMAKE_BINARY_DIR}/" binary_prefix)
    string(FIND "${binary_prefix}" "${artifacts_prefix}" artifacts_position)
    if(NOT artifacts_position EQUAL 0)
        message(FATAL_ERROR "Configure UniversalDevKit inside !artifacts: use a preset or -B !artifacts/<platform>/cmake/<project>")
    endif()
endif()

project(UniversalDevKit VERSION 0.1.0 LANGUAGES CXX)

# INTERFACE передаёт заголовки и требования C++ потребителю, не создавая библиотеку.
add_library(universaldevkit_headers INTERFACE)
add_library(UniversalDevKit::Headers ALIAS universaldevkit_headers)

# До установки заголовки берутся из репозитория, после — из каталога пакета.
target_include_directories(universaldevkit_headers INTERFACE
    "$<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/Includes>"
    "$<INSTALL_INTERFACE:include>"
)
target_compile_features(universaldevkit_headers INTERFACE cxx_std_17)

include(GNUInstallDirs)
include(CMakePackageConfigHelpers)

# Каждый компонент самостоятельно создаёт Static/Dynamic targets и их зависимости.
add_subdirectory("Projects/Cmake/Helpers")
add_subdirectory("Projects/Cmake/Diagnostic")

# Установка объединяет библиотеки и требования к ним в один набор экспорта.
set_target_properties(universaldevkit_headers PROPERTIES EXPORT_NAME Headers)
install(TARGETS universaldevkit_headers ${universaldevkit_component_targets} EXPORT UniversalDevKitTargets
    ARCHIVE DESTINATION "${CMAKE_INSTALL_LIBDIR}"
    LIBRARY DESTINATION "${CMAKE_INSTALL_LIBDIR}"
    RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}"
)
install(DIRECTORY "Includes/" DESTINATION "include")
# Namespace + EXPORT_NAME дают, например, UniversalDevKit::Helpers.Static.
install(EXPORT UniversalDevKitTargets
    NAMESPACE UniversalDevKit::
    DESTINATION "${CMAKE_INSTALL_LIBDIR}/cmake/UniversalDevKit"
)
# Config загружает targets для find_package; ConfigVersion проверяет версию пакета.
configure_package_config_file(
    "Projects/Cmake/UniversalDevKitConfig.cmake.in"
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