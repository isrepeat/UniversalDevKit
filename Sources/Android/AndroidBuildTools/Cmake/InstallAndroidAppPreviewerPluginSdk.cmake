function(fn_androidappkit_install_android_app_previewer_plugin_sdk packages_root package_source)
    if(NOT ANDROID_UDK_VERSION)
        message(FATAL_ERROR "ANDROID_UDK_VERSION must match the AndroidTemplates UdkVersion.")
    endif()
    set(package_name UniversalDevKit.AndroidAppPreviewer.PluginSDK)
    set(package_directory "${packages_root}/sdk-${ANDROID_UDK_VERSION}")
    if(NOT EXISTS "${package_directory}/cmake/AndroidAppPreviewerPluginConfig.cmake")
        set(package_archive "${package_source}/${package_name}.${ANDROID_UDK_VERSION}.nupkg")
        if(EXISTS "${package_archive}")
            file(MAKE_DIRECTORY "${package_directory}")
            execute_process(COMMAND "${CMAKE_COMMAND}" -E tar xf "${package_archive}"
                WORKING_DIRECTORY "${package_directory}" COMMAND_ERROR_IS_FATAL ANY)
        else()
            find_program(nuget_executable NAMES nuget.exe REQUIRED)
            string(RANDOM LENGTH 16 ALPHABET 0123456789abcdef restore_id)
            file(TO_CMAKE_PATH "$ENV{TEMP}/udk-preview-${restore_id}" restore_root)
            execute_process(
                COMMAND "${nuget_executable}" install "${package_name}"
                    -Version "${ANDROID_UDK_VERSION}"
                    -Source "${package_source}"
                    -OutputDirectory "${restore_root}"
                    -NonInteractive -ForceEnglishOutput -Verbosity quiet
                COMMAND_ERROR_IS_FATAL ANY)
            file(COPY "${restore_root}/${package_name}.${ANDROID_UDK_VERSION}/" DESTINATION "${package_directory}")
            file(REMOVE_RECURSE "${restore_root}")
        endif()
    endif()
    unset(AndroidAppPreviewerPlugin_DIR CACHE)
    find_package(AndroidAppPreviewerPlugin CONFIG REQUIRED
        PATHS "${package_directory}/cmake" NO_DEFAULT_PATH NO_CMAKE_FIND_ROOT_PATH)
endfunction()