function(udkReadManifest path xmlRoot output)
    if(NOT path MATCHES "\\.(json|xml)$")
        if(EXISTS "${path}.json")
            set(path "${path}.json")
        else()
            # Detect the addition of a higher-priority JSON description.
            file(GLOB manifestJson CONFIGURE_DEPENDS "${path}.json")
            set(path "${path}.xml")
        endif()
    endif()
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${path}")
    if(path MATCHES "\\.xml$")
        find_program(UDK_MANIFEST_POWERSHELL NAMES pwsh powershell REQUIRED)
        set(converter "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/../../Sources/Windows/UdkCli/Tools/ConvertManifestToJson.ps1")
        set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${converter}"
            "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/../../Sources/Windows/UdkCli/Tools/ReadManifest.ps1")
        execute_process(
            COMMAND "${UDK_MANIFEST_POWERSHELL}" -NoProfile -ExecutionPolicy Bypass -File "${converter}" -Path "${path}" -XmlRoot "${xmlRoot}"
            OUTPUT_VARIABLE json
            ERROR_VARIABLE error
            RESULT_VARIABLE result
            ENCODING UTF-8
        )
        if(NOT result STREQUAL "0")
            message(FATAL_ERROR "Cannot read ${path}: ${error}")
        endif()
    else()
        file(READ "${path}" json)
    endif()
    set("${output}" "${json}" PARENT_SCOPE)
endfunction()