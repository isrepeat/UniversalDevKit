cmake_minimum_required(VERSION 3.22)
project({{Application}} LANGUAGES CXX)
if(ANDROID)
    find_package(udk_openglesrenderer_static CONFIG REQUIRED)
    find_package(udk_diagnostic_dynamic CONFIG REQUIRED)
    get_target_property(udk_include udk_openglesrenderer_static::OpenGLESRenderer INTERFACE_INCLUDE_DIRECTORIES)
    include("${udk_include}/UniversalDevKit/Android/Consumer.cmake")
    add_library(UDK::Diagnostic ALIAS udk_diagnostic_dynamic::Diagnostic)
    add_library(UDK::XamlRuntime ALIAS udk_openglesrenderer_static::OpenGLESRenderer)
else()
    set(CMAKE_CONFIGURATION_TYPES "Debug;Release" CACHE STRING "Supported preview configurations" FORCE)
    if(NOT ANDROID_BUILD_TOOLS_ROOT)
        execute_process(COMMAND powershell.exe -NoProfile -ExecutionPolicy Bypass
            -File "${CMAKE_CURRENT_SOURCE_DIR}/build.ps1" -Command restore
            OUTPUT_VARIABLE tools_output OUTPUT_STRIP_TRAILING_WHITESPACE COMMAND_ERROR_IS_FATAL ANY)
        string(REGEX MATCH "[^\r\n]+$" ANDROID_BUILD_TOOLS_ROOT "${tools_output}")
        file(TO_CMAKE_PATH "${ANDROID_BUILD_TOOLS_ROOT}" ANDROID_BUILD_TOOLS_ROOT)
    endif()
    if(NOT ANDROID_PACKAGES_FEED)
        execute_process(COMMAND powershell.exe -NoProfile -ExecutionPolicy Bypass
            -File "${CMAKE_CURRENT_SOURCE_DIR}/build.ps1" -Command get-packages-feed
            OUTPUT_VARIABLE ANDROID_PACKAGES_FEED OUTPUT_STRIP_TRAILING_WHITESPACE COMMAND_ERROR_IS_FATAL ANY)
    endif()
    if(NOT ANDROID_UDK_VERSION)
        execute_process(COMMAND powershell.exe -NoProfile -ExecutionPolicy Bypass
            -File "${CMAKE_CURRENT_SOURCE_DIR}/build.ps1" -Command get-configuration-value -Name UdkVersion
            OUTPUT_VARIABLE ANDROID_UDK_VERSION OUTPUT_STRIP_TRAILING_WHITESPACE COMMAND_ERROR_IS_FATAL ANY)
    endif()
    include("${ANDROID_BUILD_TOOLS_ROOT}/cmake/AndroidBuildConfiguration.cmake")
    include("${ANDROID_BUILD_TOOLS_ROOT}/cmake/InstallAndroidAppPreviewerPluginSdk.cmake")
    fn_androidappkit_get_configuration_path("${CMAKE_CURRENT_SOURCE_DIR}" PackageDirectories.AndroidAppPreviewerPluginSdk preview_sdk_packages)
    fn_androidappkit_install_android_app_previewer_plugin_sdk("${preview_sdk_packages}" "${ANDROID_PACKAGES_FEED}")
    execute_process(COMMAND powershell.exe -NoProfile -ExecutionPolicy Bypass
        -File "${ANDROID_BUILD_TOOLS_ROOT}/tools/Resolve-AndroidAppPreviewer.ps1"
        -PackagesRoot "${preview_sdk_packages}" -Source "${ANDROID_PACKAGES_FEED}" -Version "${ANDROID_UDK_VERSION}"
        OUTPUT_VARIABLE previewer_restore_output COMMAND_ERROR_IS_FATAL ANY)
    add_library(UDK::Diagnostic ALIAS UniversalDevKit::Diagnostic.Dynamic)
    add_library(UDK::XamlRuntime ALIAS UniversalDevKit::XamlRuntime.Static)
endif()
include("${ANDROID_BUILD_TOOLS_ROOT}/cmake/AndroidBuildConfiguration.cmake")
include("${ANDROID_BUILD_TOOLS_ROOT}/cmake/AndroidApplicationFramework.cmake")
add_subdirectory({{Application}}.Application)
if(ANDROID)
    add_subdirectory({{Application}}.AndroidHost)
    udk_android_link({{application}} udk_openglesrenderer_static::OpenGLESRenderer)
    udk_android_link({{application}} udk_diagnostic_dynamic::Diagnostic)
else()
    add_subdirectory({{Application}}.PreviewPlugin)
endif()