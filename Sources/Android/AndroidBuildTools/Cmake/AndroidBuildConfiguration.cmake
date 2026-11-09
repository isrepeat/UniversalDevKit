include_guard(GLOBAL)

function(fn_androidappkit_get_configuration_path project_root configuration_name output_variable)
    string(REPLACE "." "_" androidappkit_configuration_key "${configuration_name}")
    set(androidappkit_configuration_key "ANDROID_BUILD_CONFIGURATION_${androidappkit_configuration_key}")
    if (DEFINED ${androidappkit_configuration_key})
        file(TO_CMAKE_PATH "${${androidappkit_configuration_key}}" androidappkit_configuration_path)
    else()
        find_program(androidappkit_configuration_powershell NAMES powershell.exe REQUIRED)
        execute_process(
            COMMAND "${androidappkit_configuration_powershell}" -NoProfile -ExecutionPolicy Bypass
                -File "${project_root}/build.ps1" -Command get-configuration-path -Name "${configuration_name}"
            RESULT_VARIABLE androidappkit_configuration_result
            OUTPUT_VARIABLE androidappkit_configuration_output
            ERROR_VARIABLE androidappkit_configuration_error
            OUTPUT_STRIP_TRAILING_WHITESPACE)
        if (NOT androidappkit_configuration_result EQUAL 0)
            message(FATAL_ERROR "Could not read ${configuration_name}: ${androidappkit_configuration_error}")
        endif()
        string(REGEX MATCH "[^\r\n]+$" androidappkit_configuration_path "${androidappkit_configuration_output}")
        file(TO_CMAKE_PATH "${androidappkit_configuration_path}" androidappkit_configuration_path)
    endif()
    set(${output_variable} "${androidappkit_configuration_path}" PARENT_SCOPE)
endfunction()

function(fn_androidappkit_generate_xaml project_root)
    get_filename_component(androidappkit_project_root "${project_root}" ABSOLUTE)
    file(TO_CMAKE_PATH "$ENV{ANDROID_BUILD_XAML_GENERATED_PROJECT}" androidappkit_generated_project)
    if (androidappkit_project_root STREQUAL androidappkit_generated_project)
        return()
    endif()
    get_filename_component(androidappkit_tools_directory "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/../tools" ABSOLUTE)
    execute_process(
        COMMAND powershell.exe -NoProfile -ExecutionPolicy Bypass
            -File "${androidappkit_tools_directory}/generate-xaml.ps1" -ProjectRoot "${androidappkit_project_root}"
        WORKING_DIRECTORY "${androidappkit_project_root}"
        COMMAND_ERROR_IS_FATAL ANY)
endfunction()

function(fn_androidappkit_write_if_changed path contents)
    set(androidappkit_existing_contents "")
    if (EXISTS "${path}")
        file(READ "${path}" androidappkit_existing_contents)
    endif()
    # Сохраняем время неизменённого файла, чтобы не запускать лишнюю компиляцию.
    if (NOT EXISTS "${path}" OR NOT androidappkit_existing_contents STREQUAL contents)
        file(WRITE "${path}" "${contents}")
    endif()
endfunction()