include_guard(GLOBAL)
get_filename_component(udkPreviewSdkRoot "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
unset(UniversalDevKit_DIR CACHE)
find_package(UniversalDevKit CONFIG REQUIRED COMPONENTS XamlRuntime OpenGLESRenderer Diagnostic
    PATHS "${udkPreviewSdkRoot}/native/lib/cmake/UniversalDevKit" NO_DEFAULT_PATH)
add_library(AndroidAppPreviewerPlugin::SDK INTERFACE IMPORTED GLOBAL)
set_target_properties(AndroidAppPreviewerPlugin::SDK PROPERTIES
    INTERFACE_INCLUDE_DIRECTORIES "${udkPreviewSdkRoot}/include"
    INTERFACE_LINK_LIBRARIES "UniversalDevKit::OpenGLESRenderer.Static;UniversalDevKit::Diagnostic.Dynamic;UniversalDevKit::ANGLE")

function(android_app_previewer_add_runtime target_name)
    get_filename_component(udkPreviewSdkRoot "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/.." ABSOLUTE)
    file(GLOB_RECURSE sources CONFIGURE_DEPENDS "${udkPreviewSdkRoot}/src/*.cpp")
    target_sources(${target_name} PRIVATE ${sources})
    target_include_directories(${target_name} PRIVATE "${udkPreviewSdkRoot}/src")
    target_link_libraries(${target_name} PRIVATE AndroidAppPreviewerPlugin::SDK)
    target_compile_definitions(${target_name} PRIVATE NOMINMAX WIN32_LEAN_AND_MEAN)
    if(MSVC)
        target_compile_options(${target_name} PRIVATE /utf-8 /EHsc)
    endif()
    udk_xaml_copy_runtime(${target_name})
endfunction()