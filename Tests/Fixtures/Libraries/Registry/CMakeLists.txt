cmake_minimum_required(VERSION 3.22)
project(RegistryFixture VERSION 0.1.0 LANGUAGES CXX)
if(UDK_TEST_PLATFORM)
    # Используется только для проверки отказа до создания targets, без имитации toolchain.
    set(CMAKE_SYSTEM_NAME "${UDK_TEST_PLATFORM}")
endif()

add_library(headers INTERFACE)
add_library(UniversalDevKit::Headers ALIAS headers)
target_include_directories(headers INTERFACE "$<BUILD_INTERFACE:${CMAKE_CURRENT_LIST_DIR}/Includes>" "$<INSTALL_INTERFACE:include>")
target_compile_features(headers INTERFACE cxx_std_17)
set(UniversalDevKit_COMPONENTS Example CACHE STRING "Fixture roots")
set(UniversalDevKit_BUILD_STATIC ON)
set(UniversalDevKit_BUILD_DYNAMIC OFF)
include("${CMAKE_CURRENT_LIST_DIR}/../../../../Projects/Cmake/ComponentDependencies.cmake")
get_target_property(files universaldevkit_example SOURCES)
list(FILTER files INCLUDE REGEX "\\.cpp$")
list(LENGTH files count)
if(NOT count EQUAL 2)
    message(FATAL_ERROR "Expected common and Windows sources: ${files}")
endif()

if(TARGET UniversalDevKit::Service.Static)
    message(FATAL_ERROR "Process-state service must not have a Static target")
endif()

foreach(plugin IN ITEMS A B)
    add_library(plugin${plugin} SHARED Plugin.cpp)
    target_link_libraries(plugin${plugin} PRIVATE UniversalDevKit::Example.Static)
    target_compile_definitions(plugin${plugin} PRIVATE PLUGIN_${plugin})
endforeach()

add_executable(state_consumer Main.cpp)
target_link_libraries(state_consumer PRIVATE pluginA pluginB UniversalDevKit::Example.Static)
if(WIN32)
    add_custom_command(TARGET state_consumer POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            $<TARGET_RUNTIME_DLLS:state_consumer> $<TARGET_FILE_DIR:state_consumer>
        COMMAND_EXPAND_LISTS
    )
endif()

enable_testing()
add_test(NAME ProcessState COMMAND state_consumer)

# Экспорт нового компонента проверяется тем же Config-шаблоном, что и основной пакет.
set_target_properties(headers PROPERTIES EXPORT_NAME Headers)
include(CMakePackageConfigHelpers)
install(TARGETS headers ${exportedComponentTargets} EXPORT UniversalDevKitTargets ARCHIVE DESTINATION lib LIBRARY DESTINATION lib RUNTIME DESTINATION bin)
install(DIRECTORY Includes/ DESTINATION include)
install(EXPORT UniversalDevKitTargets NAMESPACE UniversalDevKit:: DESTINATION lib/cmake/UniversalDevKit)
configure_package_config_file("${CMAKE_CURRENT_LIST_DIR}/../../../../Projects/Cmake/UniversalDevKitConfig.cmake.in" "${CMAKE_CURRENT_BINARY_DIR}/UniversalDevKitConfig.cmake" INSTALL_DESTINATION lib/cmake/UniversalDevKit)
write_basic_package_version_file("${CMAKE_CURRENT_BINARY_DIR}/UniversalDevKitConfigVersion.cmake" COMPATIBILITY SameMinorVersion)
install(FILES "${CMAKE_CURRENT_BINARY_DIR}/UniversalDevKitConfig.cmake" "${CMAKE_CURRENT_BINARY_DIR}/UniversalDevKitConfigVersion.cmake" DESTINATION lib/cmake/UniversalDevKit)