function(udk_extend_GeneratedProbe target variant outputRoot)
    set(generator "${PROJECT_SOURCE_DIR}/Projects/Generation/Generate.cmake")
    set(input "${PROJECT_SOURCE_DIR}/Projects/Generation/Input.txt")
    set(header "${outputRoot}/Includes/UniversalDevKit/GeneratedProbe/Generated/Value.h")
    set(source "${outputRoot}/Sources/Value.cpp")
    add_custom_command(OUTPUT "${header}" "${source}"
        COMMAND "${CMAKE_COMMAND}" "-DOUTPUT_ROOT=${outputRoot}" "-DINPUT_FILE=${input}" -P "${generator}"
        DEPENDS "${input}" "${generator}"
        VERBATIM
    )
    target_sources(${target} PRIVATE "${source}" "${header}")
    target_include_directories(${target} PUBLIC "$<BUILD_INTERFACE:${outputRoot}/Includes>")
    # Заголовок доступен consumer только после завершения генерации библиотеки.
    if(UniversalDevKit_INSTALL)
        install(FILES "${header}" DESTINATION "include/UniversalDevKit/GeneratedProbe/Generated")
    endif()
endfunction()