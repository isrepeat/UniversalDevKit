function(fn_androidappkit_install_android_app_previewer_plugin_sdk packages_root package_source)
    if(NOT ANDROID_UDK_VERSION)
        message(FATAL_ERROR "ANDROID_UDK_VERSION must match the AndroidTemplates UdkVersion.")
    endif()
    set(package_name UniversalDevKit.AndroidAppPreviewer.PluginSDK)
    set(package_directory "${packages_root}/${package_name}.${ANDROID_UDK_VERSION}")
    # Restore the package and its NuGet dependencies together.
    find_program(nuget_executable NAMES nuget.exe REQUIRED)
    execute_process(
        COMMAND "${nuget_executable}" install "${package_name}"
            -Version "${ANDROID_UDK_VERSION}"
            -Source "${package_source}"
            -OutputDirectory "${packages_root}"
            -NonInteractive -ForceEnglishOutput -Verbosity quiet
        COMMAND_ERROR_IS_FATAL ANY)
    unset(AndroidAppPreviewerPlugin_DIR CACHE)
    find_package(AndroidAppPreviewerPlugin CONFIG REQUIRED
        PATHS "${package_directory}/cmake" NO_DEFAULT_PATH NO_CMAKE_FIND_ROOT_PATH)
endfunction()