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

include("Projects/Cmake/Version.cmake")
project(UniversalDevKit VERSION ${udkReleaseVersion} LANGUAGES CXX)

# Настройка принадлежит UDK и не меняет глобальные параметры consumer.
set(UniversalDevKitRuntime "Dynamic" CACHE STRING "MSVC runtime: Dynamic (MD) or Static (MT)")
set_property(CACHE UniversalDevKitRuntime PROPERTY STRINGS Dynamic Static)
if(NOT UniversalDevKitRuntime MATCHES "^(Dynamic|Static)$")
    message(FATAL_ERROR "UniversalDevKitRuntime must be Dynamic (MD) or Static (MT)")
endif()
set(udkMsvcRuntime "MultiThreaded$<$<CONFIG:Debug>:Debug>")
if(UniversalDevKitRuntime STREQUAL "Dynamic")
    string(APPEND udkMsvcRuntime "DLL")
endif()
if(MSVC AND DEFINED CMAKE_MSVC_RUNTIME_LIBRARY AND NOT CMAKE_MSVC_RUNTIME_LIBRARY STREQUAL udkMsvcRuntime)
    message(FATAL_ERROR "CMAKE_MSVC_RUNTIME_LIBRARY conflicts with UniversalDevKitRuntime; select the same runtime explicitly")
endif()

# Один build-каталог закреплён за компилятором, архитектурой и CRT.
set(udkBuildIdentity "${CMAKE_SYSTEM_NAME}|${CMAKE_SYSTEM_PROCESSOR}|${CMAKE_SIZEOF_VOID_P}|${CMAKE_CXX_COMPILER}|${CMAKE_CXX_COMPILER_VERSION}|${CMAKE_VS_PLATFORM_TOOLSET}|${UniversalDevKitRuntime}")
set(udkBuildIdentityPath "${CMAKE_CURRENT_BINARY_DIR}/UniversalDevKitBuildIdentity.txt")
if(EXISTS "${udkBuildIdentityPath}")
    file(READ "${udkBuildIdentityPath}" previousUdkBuildIdentity)
    if(NOT previousUdkBuildIdentity STREQUAL udkBuildIdentity)
        message(FATAL_ERROR "UniversalDevKit compiler/architecture/runtime changed: use a separate build directory")
    endif()
endif()
configure_file("Projects/Cmake/BuildIdentity.txt.in" "${udkBuildIdentityPath}" @ONLY)

set(UniversalDevKit_COMPONENTS "ALL" CACHE STRING "Components to build; ALL or a semicolon-separated list")
option(UniversalDevKit_BUILD_STATIC "Build static variants" ON)
option(UniversalDevKit_BUILD_DYNAMIC "Build dynamic variants" ON)
option(UniversalDevKit_INSTALL "Generate installation rules" ON)

# INTERFACE передаёт заголовки и требования C++ потребителю, не создавая библиотеку.
add_library(universaldevkit_headers INTERFACE)
add_library(UniversalDevKit::Headers ALIAS universaldevkit_headers)

# До установки заголовки берутся из репозитория, после — из каталога пакета.
target_include_directories(universaldevkit_headers INTERFACE
    "$<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/Includes/Core>"
    "$<INSTALL_INTERFACE:include>"
)
target_compile_features(universaldevkit_headers INTERFACE cxx_std_17)

include(GNUInstallDirs)
include(CMakePackageConfigHelpers)

# Каждый компонент самостоятельно создаёт Static/Dynamic targets и их зависимости.
include("Projects/Cmake/ComponentDependencies.cmake")

# Установка объединяет библиотеки и требования к ним в один набор экспорта.
if(UniversalDevKit_INSTALL)
set_target_properties(universaldevkit_headers PROPERTIES EXPORT_NAME Headers)
install(TARGETS universaldevkit_headers ${exportedComponentTargets} EXPORT UniversalDevKitTargets
    ARCHIVE DESTINATION "${CMAKE_INSTALL_LIBDIR}"
    LIBRARY DESTINATION "${CMAKE_INSTALL_LIBDIR}"
    RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}"
)
install(DIRECTORY "Includes/Core/" DESTINATION "include")
foreach(componentName IN LISTS availablePackageComponents)
    install(DIRECTORY "Includes/${componentName}/" DESTINATION "include")
endforeach()
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
    COMPATIBILITY SameMinorVersion
)
install(FILES
    "${CMAKE_CURRENT_BINARY_DIR}/UniversalDevKitConfig.cmake"
    "${CMAKE_CURRENT_BINARY_DIR}/UniversalDevKitConfigVersion.cmake"
    DESTINATION "${CMAKE_INSTALL_LIBDIR}/cmake/UniversalDevKit"
)
endif()