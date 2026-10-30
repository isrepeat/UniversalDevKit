cmake_minimum_required(VERSION 3.22)
project(UniversalDevKitXamlRuntime LANGUAGES CXX)

get_filename_component(udkRoot "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)
if(CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
    file(TO_CMAKE_PATH "${udkRoot}/!artifacts/" artifactPrefix)
    file(TO_CMAKE_PATH "${CMAKE_BINARY_DIR}/" buildPrefix)
    string(FIND "${buildPrefix}" "${artifactPrefix}" artifactPosition)
    if(NOT artifactPosition EQUAL 0)
        message(FATAL_ERROR "Configure this temporary project inside UDK !artifacts")
    endif()
endif()

option(UniversalDevKitXaml_BUILD_RENDERER "Build the OpenGL ES renderer" ON)
option(UniversalDevKitXaml_BUILD_COMPILER "Build the host XAML compiler" ON)
option(UniversalDevKitXaml_BUILD_TESTS "Build the existing color animation regression test" ON)
set(UniversalDevKitXaml_ANGLE_ROOT "" CACHE PATH "ANGLE installation or extracted legacy package (Windows)")

if(NOT WIN32 AND NOT ANDROID)
    message(FATAL_ERROR "The temporary legacy logging backend supports Windows and Android only")
endif()
if(ANDROID AND (UniversalDevKitXaml_BUILD_COMPILER OR UniversalDevKitXaml_BUILD_TESTS))
    message(FATAL_ERROR "Build the host compiler separately; disable compiler and tests for the Android cross-build")
endif()

set(legacyRoot "${udkRoot}/Sources/XamlRuntime/LegacyLogging")
add_library(udk_xaml_legacy_logging STATIC "${legacyRoot}/Helpers.Logging/Logging.cpp")
target_include_directories(udk_xaml_legacy_logging PRIVATE "${legacyRoot}" "${udkRoot}/ThirdParty/spdlog/include")
if(ANDROID)
    target_sources(udk_xaml_legacy_logging PRIVATE "${legacyRoot}/Helpers.Logging/platform/android/LoggingBackendAndroid.cpp")
    target_link_libraries(udk_xaml_legacy_logging PRIVATE log)
else()
    target_sources(udk_xaml_legacy_logging PRIVATE "${legacyRoot}/Helpers.Logging/platform/windows/LoggingBackendWindows.cpp")
endif()
target_compile_features(udk_xaml_legacy_logging PRIVATE cxx_std_20)
set_target_properties(udk_xaml_legacy_logging PROPERTIES POSITION_INDEPENDENT_CODE ON)

set(runtimeSources
    Animation.cpp Binding.cpp ElementBuilder.cpp GestureRecognizer.cpp Input.cpp
    InteractionController.cpp RenderEngine.cpp ScrollController.cpp UserControl.cpp
    VisualState.cpp XamlAttribute.cpp XamlLayout.cpp
    RuntimeMarkup/RuntimeBindingRegistry.cpp RuntimeMarkup/RuntimeReloadTransaction.cpp
    RuntimeMarkup/RuntimeTreeBuilder.cpp RuntimeMarkup/XamlParser.cpp RuntimeMarkup/XamlSchemaValidator.cpp
)
list(TRANSFORM runtimeSources PREPEND "${udkRoot}/Sources/XamlRuntime/")
add_library(udk_xaml_runtime STATIC ${runtimeSources})
add_library(UniversalDevKit::XamlRuntime.Static ALIAS udk_xaml_runtime)
add_library(XamlRuntime::Runtime ALIAS udk_xaml_runtime)
target_include_directories(udk_xaml_runtime PUBLIC "${udkRoot}/Includes/XamlRuntime")
target_include_directories(udk_xaml_runtime PRIVATE "${legacyRoot}" "${udkRoot}/ThirdParty/spdlog/include")
target_link_libraries(udk_xaml_runtime PRIVATE udk_xaml_legacy_logging)
target_compile_features(udk_xaml_runtime PUBLIC cxx_std_20)
set_target_properties(udk_xaml_runtime PROPERTIES POSITION_INDEPENDENT_CODE ON)

if(UniversalDevKitXaml_BUILD_RENDERER)
    add_library(udk_xaml_renderer STATIC
        "${udkRoot}/Sources/OpenGLESRenderer/OpenGlRenderer.cpp"
        "${udkRoot}/Sources/OpenGLESRenderer/StandardShaders.cpp"
    )
    add_library(UniversalDevKit::OpenGLESRenderer.Static ALIAS udk_xaml_renderer)
    add_library(XamlRuntime::OpenGLESRenderer ALIAS udk_xaml_renderer)
    target_include_directories(udk_xaml_renderer PUBLIC "${udkRoot}/Includes/OpenGLESRenderer")
    target_include_directories(udk_xaml_renderer PRIVATE "${legacyRoot}" "${udkRoot}/ThirdParty/spdlog/include")
    target_link_libraries(udk_xaml_renderer PUBLIC udk_xaml_runtime PRIVATE udk_xaml_legacy_logging)
    set_target_properties(udk_xaml_renderer PROPERTIES POSITION_INDEPENDENT_CODE ON)
    if(ANDROID)
        target_link_libraries(udk_xaml_renderer PRIVATE GLESv3)
    else()
        find_path(angleInclude GLES3/gl3.h PATHS "${UniversalDevKitXaml_ANGLE_ROOT}/include" "${UniversalDevKitXaml_ANGLE_ROOT}/build/native/include" NO_DEFAULT_PATH REQUIRED)
        foreach(library EGL GLESv2)
            find_library(angle${library} NAMES lib${library} PATHS
                "${UniversalDevKitXaml_ANGLE_ROOT}/lib"
                "${UniversalDevKitXaml_ANGLE_ROOT}/runtimes/win-x64/native/Release"
                NO_DEFAULT_PATH REQUIRED)
            target_link_libraries(udk_xaml_renderer PRIVATE "${angle${library}}")
        endforeach()
        target_include_directories(udk_xaml_renderer SYSTEM PRIVATE "${angleInclude}")
    endif()
endif()

if(UniversalDevKitXaml_BUILD_COMPILER)
    add_subdirectory("${udkRoot}/Projects/Cmake/XamlCompiler" "${CMAKE_CURRENT_BINARY_DIR}/XamlCompiler")
endif()

if(MSVC)
    foreach(target udk_xaml_legacy_logging udk_xaml_runtime udk_xaml_renderer)
        if(TARGET ${target})
            target_compile_options(${target} PRIVATE /utf-8 /EHsc)
        endif()
    endforeach()
endif()

if(UniversalDevKitXaml_BUILD_TESTS)
    if(NOT TARGET udk_xaml_compiler)
        message(FATAL_ERROR "The color animation test requires the host compiler")
    endif()
    enable_testing()
    set(testMarkup "${udkRoot}/Tests/XamlRuntime/ColorAnimationPage.xaml")
    set(testGenerated "${CMAKE_CURRENT_BINARY_DIR}/generated/ColorAnimationPage.xaml.cpp")
    add_custom_command(OUTPUT "${testGenerated}" "${CMAKE_CURRENT_BINARY_DIR}/generated/ColorAnimationPage.xaml.h"
        COMMAND $<TARGET_FILE:udk_xaml_compiler> "${testMarkup}" "${testGenerated}"
        DEPENDS udk_xaml_compiler "${testMarkup}" VERBATIM)
    add_executable(udk_xaml_color_animation_tests "${udkRoot}/Tests/XamlRuntime/ColorAnimationTests.cpp" "${testGenerated}")
    target_include_directories(udk_xaml_color_animation_tests PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/generated")
    target_link_libraries(udk_xaml_color_animation_tests PRIVATE udk_xaml_runtime)
    if(MSVC)
        target_compile_options(udk_xaml_color_animation_tests PRIVATE /utf-8 /EHsc)
    endif()
    add_test(NAME XamlRuntime.ColorAnimation COMMAND udk_xaml_color_animation_tests "${testMarkup}")
endif()