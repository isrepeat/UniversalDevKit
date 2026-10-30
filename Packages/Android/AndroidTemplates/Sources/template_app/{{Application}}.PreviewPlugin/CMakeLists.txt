file(GLOB_RECURSE {{application}}_preview_plugin_sources CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/*.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/*.h")
source_group(TREE "${CMAKE_CURRENT_SOURCE_DIR}" FILES ${{{application}}_preview_plugin_sources})
set({{application}}_preview_generated_root
    "${CMAKE_CURRENT_SOURCE_DIR}/../!Generated/{{Application}}.Application/Xaml")
file(GLOB_RECURSE {{application}}_preview_generated_headers CONFIGURE_DEPENDS
    "${{{application}}_preview_generated_root}/*.h")
if (NOT {{application}}_preview_generated_headers)
    message(FATAL_ERROR "XamlCompiler did not generate headers for {{Application}}.PreviewPlugin.")
endif()
add_library({{application}}_preview_plugin SHARED ${{{application}}_preview_plugin_sources})
set_target_properties({{application}}_preview_plugin PROPERTIES
    OUTPUT_NAME {{Application}}.PreviewPlugin
    CXX_STANDARD 20
    CXX_STANDARD_REQUIRED ON
    CXX_EXTENSIONS OFF
    WINDOWS_EXPORT_ALL_SYMBOLS OFF
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_SOURCE_DIR}/Build/{{Application}}.PreviewPlugin/Build/$<CONFIG>/x64/{{Application}}.PreviewPlugin")
android_app_previewer_add_runtime({{application}}_preview_plugin)

target_include_directories({{application}}_preview_plugin PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/..")
target_link_libraries({{application}}_preview_plugin PRIVATE
    AndroidAppPreviewerPlugin::SDK
    {{application}}_application
    XamlRuntime::Logging
    XamlRuntime::Runtime
    XamlRuntime::OpenGLESRenderer)
if (MSVC)
    target_compile_options({{application}}_preview_plugin PRIVATE /utf-8)
endif()
target_compile_definitions({{application}}_preview_plugin PRIVATE
    {{APPLICATION}}_PREVIEW_SOURCE_MARKUP_DIRECTORY="${CMAKE_CURRENT_SOURCE_DIR}/../{{Application}}.Application/UI"
    {{APPLICATION}}_PREVIEW_SOURCE_ENTRY_MARKUP_PATH="${CMAKE_CURRENT_SOURCE_DIR}/../{{Application}}.Application/UI/Page/MainPage.xaml"
    {{APPLICATION}}_PREVIEW_SOURCE_CONTROLS_DIRECTORY="${CMAKE_CURRENT_SOURCE_DIR}/../{{Application}}.UI/Control")

# ANGLE ищет свои DLL рядом с загруженным плагином.
get_target_property({{application}}_angle_runtime_library XamlRuntime::OpenGLESRenderer IMPORTED_LOCATION)
get_filename_component({{application}}_angle_runtime_directory "${{{application}}_angle_runtime_library}" DIRECTORY)
set({{application}}_angle_runtime_files libEGL.dll libGLESv2.dll z.dll)
if (CMAKE_BUILD_TYPE STREQUAL "Debug")
    set({{application}}_angle_runtime_files libEGL.dll libGLESv2.dll zd.dll)
endif()
foreach ({{application}}_angle_runtime_file IN LISTS {{application}}_angle_runtime_files)
    add_custom_command(TARGET {{application}}_preview_plugin POST_BUILD
        COMMAND "${CMAKE_COMMAND}" -E copy_if_different
            "${{{application}}_angle_runtime_directory}/${{{application}}_angle_runtime_file}"
            "$<TARGET_FILE_DIR:{{application}}_preview_plugin>/${{{application}}_angle_runtime_file}")
endforeach()

set({{application}}_preview_resources "${CMAKE_CURRENT_SOURCE_DIR}/../{{Application}}.Application/Resources")
if (EXISTS "${{{application}}_preview_resources}")
    file(GLOB_RECURSE {{application}}_preview_resource_files CONFIGURE_DEPENDS "${{{application}}_preview_resources}/*")
    source_group(TREE "${{{application}}_preview_resources}" PREFIX "Resources" FILES ${{{application}}_preview_resource_files})
    target_sources({{application}}_preview_plugin PRIVATE ${{{application}}_preview_resource_files})
    add_custom_command(TARGET {{application}}_preview_plugin POST_BUILD
        COMMAND "${CMAKE_COMMAND}" -E copy_directory
            "${{{application}}_preview_resources}" "$<TARGET_FILE_DIR:{{application}}_preview_plugin>/Resources")
else()
    add_custom_command(TARGET {{application}}_preview_plugin POST_BUILD
        COMMAND "${CMAKE_COMMAND}" -E make_directory "$<TARGET_FILE_DIR:{{application}}_preview_plugin>/Resources")
endif()