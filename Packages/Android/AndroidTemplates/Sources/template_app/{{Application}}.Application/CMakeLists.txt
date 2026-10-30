set({{application}}_project_root "${CMAKE_CURRENT_SOURCE_DIR}/..")
# Android-сборка передаёт фактическую версию; preview использует базовую версию проекта.
if (NOT DEFINED {{APPLICATION}}_PACKAGE_VERSION)
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${{{application}}_project_root}/version.properties")
    file(STRINGS "${{{application}}_project_root}/version.properties" {{application}}_version_line REGEX "^VERSION_NAME_BASE=")
    string(REGEX REPLACE "^VERSION_NAME_BASE=" "" {{application}}_version_base "${{{application}}_version_line}")
    set({{APPLICATION}}_PACKAGE_VERSION "${{{application}}_version_base}.0")
endif()
file(MAKE_DIRECTORY "${{{application}}_project_root}/!Generated/Build")
fn_androidappkit_write_if_changed("${{{application}}_project_root}/!Generated/Build/BuildVersion.h"
    "#pragma once\n#define {{APPLICATION}}_PACKAGE_VERSION \"${{{APPLICATION}}_PACKAGE_VERSION}\"")
set({{application}}_generated_root "${{{application}}_project_root}/!Generated/{{Application}}.Application/Xaml")
fn_androidappkit_generate_xaml("${{{application}}_project_root}")
file(GLOB_RECURSE {{application}}_application_sources CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/Base/*.cpp" "${CMAKE_CURRENT_SOURCE_DIR}/Base/*.h"
    "${CMAKE_CURRENT_SOURCE_DIR}/Core/*.cpp" "${CMAKE_CURRENT_SOURCE_DIR}/Core/*.h"
    "${CMAKE_CURRENT_SOURCE_DIR}/Interface/*.h"
    "${CMAKE_CURRENT_SOURCE_DIR}/Model/*.cpp" "${CMAKE_CURRENT_SOURCE_DIR}/Model/*.h"
    "${CMAKE_CURRENT_SOURCE_DIR}/UI/*.cpp" "${CMAKE_CURRENT_SOURCE_DIR}/UI/*.h")
file(GLOB_RECURSE {{application}}_generated_xaml CONFIGURE_DEPENDS "${{{application}}_generated_root}/*.xaml.cpp")
if (NOT {{application}}_generated_xaml)
    message(FATAL_ERROR "XamlCompiler did not generate application sources.")
endif()
# Генерируемые исходники и заголовки показываем отдельно от рукописного кода.
file(GLOB_RECURSE {{application}}_generated_headers CONFIGURE_DEPENDS "${{{application}}_generated_root}/*.xaml.h")
set({{application}}_generated_files
    ${{{application}}_generated_xaml}
    ${{{application}}_generated_headers}
    "${{{application}}_project_root}/!Generated/Build/BuildVersion.h")
source_group(TREE "${CMAKE_CURRENT_SOURCE_DIR}" FILES ${{{application}}_application_sources})
source_group(TREE "${{{application}}_project_root}/!Generated" PREFIX "!Generated"
    FILES ${{{application}}_generated_files})
add_custom_target({{application}}_generated SOURCES ${{{application}}_generated_files})
set_target_properties({{application}}_generated PROPERTIES FOLDER "!Generated")
add_library({{application}}_application STATIC ${{{application}}_application_sources} ${{{application}}_generated_files})
set_target_properties({{application}}_application PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_compile_features({{application}}_application PUBLIC cxx_std_20)
target_include_directories({{application}}_application PUBLIC "${{{application}}_project_root}")
target_link_libraries({{application}}_application PUBLIC
    AndroidApplication::Framework
    UDK::Diagnostic
    UDK::XamlRuntime)
if (NOT ANDROID)
    target_compile_definitions({{application}}_application PUBLIC ANDROID_APP_PREVIEWER)
endif()
if (MSVC)
    target_compile_options({{application}}_application PRIVATE /utf-8)
endif()