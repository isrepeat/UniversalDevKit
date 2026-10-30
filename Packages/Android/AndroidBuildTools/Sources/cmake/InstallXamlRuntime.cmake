function(fn_androidappkit_find_latest_xaml_runtime_package packages_root package_name output_variable)
    # Пакеты NuGet располагаются в отдельных папках <имя>.<версия>.
    # Берём наиболее новую только при наличии стандартного CMake-контракта.
    file(GLOB androidappkit_xaml_runtime_package_candidates LIST_DIRECTORIES true
        "${packages_root}/${package_name}.*")
    list(SORT androidappkit_xaml_runtime_package_candidates COMPARE NATURAL ORDER DESCENDING)
    foreach (androidappkit_xaml_runtime_package_candidate IN LISTS androidappkit_xaml_runtime_package_candidates)
        set(androidappkit_xaml_runtime_config_directory
            "${androidappkit_xaml_runtime_package_candidate}/build/native/cmake")
        if (EXISTS "${androidappkit_xaml_runtime_config_directory}/${package_name}Config.cmake")
            set(${output_variable} "${androidappkit_xaml_runtime_config_directory}" PARENT_SCOPE)
            return()
        endif()
    endforeach()
    set(${output_variable} "" PARENT_SCOPE)
endfunction()

function(fn_androidappkit_install_xaml_runtime packages_root package_source)
    set(androidappkit_xaml_runtime_package_name XamlRuntime)
    set(androidappkit_xaml_runtime_packages_root "${packages_root}")
    # Для локального feed проверяем последнюю версию без запуска NuGet.
    set(androidappkit_xaml_runtime_config_directory "")
    if (IS_DIRECTORY "${package_source}")
        file(GLOB androidappkit_xaml_archives "${package_source}/XamlRuntime.*.nupkg")
        list(FILTER androidappkit_xaml_archives INCLUDE REGEX "/XamlRuntime\\.[0-9]+\\.[0-9]+\\.[0-9]+(\\.[0-9]+)?\\.nupkg$")
        # Убираем расширение до сортировки: 1.0.25.9 должна идти выше 1.0.25.
        list(TRANSFORM androidappkit_xaml_archives REPLACE "\\.nupkg$" "")
        list(SORT androidappkit_xaml_archives COMPARE NATURAL ORDER DESCENDING)
        if (androidappkit_xaml_archives)
            list(GET androidappkit_xaml_archives 0 androidappkit_xaml_archive)
            get_filename_component(androidappkit_xaml_archive_name "${androidappkit_xaml_archive}" NAME)
            string(REGEX REPLACE "\\.nupkg$" "" androidappkit_xaml_archive_name "${androidappkit_xaml_archive_name}")
            set(androidappkit_xaml_candidate "${packages_root}/${androidappkit_xaml_archive_name}/build/native/cmake")
            if (EXISTS "${androidappkit_xaml_candidate}/XamlRuntimeConfig.cmake")
                set(androidappkit_xaml_runtime_config_directory "${androidappkit_xaml_candidate}")
            endif()
        endif()
    endif()
    if (NOT androidappkit_xaml_runtime_config_directory)
        find_program(androidappkit_nuget_executable NAMES nuget.exe REQUIRED)
        execute_process(
            COMMAND "${androidappkit_nuget_executable}" install "${androidappkit_xaml_runtime_package_name}"
                -Source "${package_source}"
                -OutputDirectory "${androidappkit_xaml_runtime_packages_root}"
                -NonInteractive
                -ForceEnglishOutput
                -Verbosity quiet
            COMMAND_ERROR_IS_FATAL ANY
        )
        fn_androidappkit_find_latest_xaml_runtime_package(
            "${androidappkit_xaml_runtime_packages_root}"
            "${androidappkit_xaml_runtime_package_name}"
            androidappkit_xaml_runtime_config_directory)
    endif()

    if (NOT androidappkit_xaml_runtime_config_directory)
        message(FATAL_ERROR "NuGet installation did not provide ${androidappkit_xaml_runtime_package_name}Config.cmake.")
    endif()
    # Не позволяем значению от предыдущей конфигурации выбрать другую копию пакета.
    unset(${androidappkit_xaml_runtime_package_name}_DIR CACHE)
    find_package(${androidappkit_xaml_runtime_package_name} CONFIG REQUIRED
        PATHS "${androidappkit_xaml_runtime_config_directory}"
        NO_DEFAULT_PATH
        # The NuGet package is on the Windows host, not in the Android NDK
        # sysroot.  Without this CMake prepends the sysroot during an Android
        # cross-compile and therefore misses the existing Config.cmake file.
        NO_CMAKE_FIND_ROOT_PATH)
endfunction()