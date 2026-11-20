target_include_directories(${componentHeadersTarget} INTERFACE
    "$<BUILD_INTERFACE:${PROJECT_SOURCE_DIR}/Includes/Diagnostic>"
)