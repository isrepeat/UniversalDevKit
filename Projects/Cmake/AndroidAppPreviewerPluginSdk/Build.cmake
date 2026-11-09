function(udk_extend_AndroidAppPreviewerPluginSdk target variant outputRoot)
    target_link_libraries(${target} PRIVATE UniversalDevKit::ANGLE)
    target_compile_options(${target} PRIVATE /utf-8 /EHsc)
endfunction()