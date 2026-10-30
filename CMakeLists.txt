cmake_minimum_required(VERSION 3.22)

# Ограничение каталога сборки действует только при самостоятельной сборке репозитория.
if(CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
    file(TO_CMAKE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/!artifacts/" artifacts_prefix)
    file(TO_CMAKE_PATH "${CMAKE_BINARY_DIR}/" binary_prefix)
    if(CMAKE_HOST_WIN32)
        # Проверяем физический каталог, сохраняя короткие пути самой сборки.
        execute_process(COMMAND subst OUTPUT_VARIABLE udk_subst_mappings RESULT_VARIABLE udk_subst_result)
        if(NOT udk_subst_result EQUAL 0)
            message(FATAL_ERROR "Cannot inspect substituted build drives")
        endif()
        string(SUBSTRING "${binary_prefix}" 0 2 udk_binary_drive)
        string(TOUPPER "${udk_binary_drive}" udk_binary_drive)
        string(REPLACE "\n" ";" udk_subst_mappings "${udk_subst_mappings}")
        foreach(udk_mapping IN LISTS udk_subst_mappings)
            string(FIND "${udk_mapping}" "${udk_binary_drive}\\: => " udk_mapping_position)
            if(udk_mapping_position EQUAL 0)
                string(SUBSTRING "${udk_mapping}" 8 -1 udk_physical_root)
                string(STRIP "${udk_physical_root}" udk_physical_root)
                string(SUBSTRING "${binary_prefix}" 2 -1 udk_binary_suffix)
                file(TO_CMAKE_PATH "${udk_physical_root}${udk_binary_suffix}" binary_prefix)
                break()
            endif()
        endforeach()
    endif()
    string(FIND "${binary_prefix}" "${artifacts_prefix}" artifacts_position)
    if(NOT artifacts_position EQUAL 0)
        message(FATAL_ERROR "Configure UniversalDevKit inside !artifacts: use a preset or -B !artifacts/projects/<platform>/cmake/<project>")
    endif()
    string(LENGTH "${artifacts_prefix}" artifacts_prefix_length)
    string(SUBSTRING "${binary_prefix}" ${artifacts_prefix_length} -1 artifact_relative_path)
    if(NOT artifact_relative_path MATCHES "^/?(projects|packages|tests)/")
        message(FATAL_ERROR "Build inside !artifacts/projects, !artifacts/packages or !artifacts/tests")
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
include("Projects/Cmake/BuildIdentity.cmake")
udkValidateBuildIdentity("${udkBuildIdentityPath}" "${udkBuildIdentity}")
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
target_compile_features(universaldevkit_headers INTERFACE cxx_std_20)

include(GNUInstallDirs)
include(CMakePackageConfigHelpers)

# Каждый компонент самостоятельно создаёт Static/Dynamic targets и их зависимости.
include("Projects/Cmake/ComponentDependencies.cmake")

# Установка объединяет библиотеки и требования к ним в один набор экспорта.
if(UniversalDevKit_INSTALL)
set(udkPackageHasBinaries FALSE)
foreach(componentTarget IN LISTS exportedComponentTargets)
    get_target_property(componentTargetType ${componentTarget} TYPE)
    if(NOT componentTargetType STREQUAL "INTERFACE_LIBRARY")
        set(udkPackageHasBinaries TRUE)
    endif()
endforeach()
set(udkPackageArchitectureOptions)
if(udkPackageHasBinaries)
    include("Projects/Cmake/PackageMetadata.cmake")
else()
    # Пакет только заголовков не имеет CRT/toolset или архитектуры бинарников.
    list(APPEND udkPackageArchitectureOptions ARCH_INDEPENDENT)
endif()
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
# Namespace + EXPORT_NAME дают, например, UniversalDevKit::HeleprsTest.Static.
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
    ${udkPackageArchitectureOptions}
)
install(FILES
    "${CMAKE_CURRENT_BINARY_DIR}/UniversalDevKitConfig.cmake"
    "${CMAKE_CURRENT_BINARY_DIR}/UniversalDevKitConfigVersion.cmake"
    DESTINATION "${CMAKE_INSTALL_LIBDIR}/cmake/UniversalDevKit"
)
endif()