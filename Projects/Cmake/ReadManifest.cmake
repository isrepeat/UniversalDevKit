function(udkReadManifest path xmlRoot output)
    if(path MATCHES "\\.json$")
        message(FATAL_ERROR "JSON manifests are unsupported. Use XML: ${path}")
    endif()
    if(NOT path MATCHES "\\.xml$")
        set(path "${path}.xml")
    endif()
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${path}")
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
    set("${output}" "${json}" PARENT_SCOPE)
endfunction()