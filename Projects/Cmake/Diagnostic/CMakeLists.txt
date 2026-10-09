# Компонент Diagnostic сам описывает варианты библиотеки и единый набор исходников.
set(universaldevkit_diagnostic_sources
    "${CMAKE_CURRENT_LIST_DIR}/../../../Sources/Diagnostic/Logging.cpp"
)

# Настоящие targets используют внутренние имена; потребители выбирают явный вариант.
add_library(universaldevkit_diagnostic STATIC ${universaldevkit_diagnostic_sources})
add_library(universaldevkit_diagnostic_dynamic SHARED ${universaldevkit_diagnostic_sources})
add_library(UniversalDevKit::Diagnostic.Static ALIAS universaldevkit_diagnostic)
add_library(UniversalDevKit::Diagnostic.Dynamic ALIAS universaldevkit_diagnostic_dynamic)

target_link_libraries(universaldevkit_diagnostic PUBLIC UniversalDevKit::Headers)
target_link_libraries(universaldevkit_diagnostic_dynamic PUBLIC UniversalDevKit::Headers)
target_compile_definitions(universaldevkit_diagnostic_dynamic
    PUBLIC UNIVERSALDEVKIT_DIAGNOSTIC_DYNAMIC
    PRIVATE UNIVERSALDEVKIT_DIAGNOSTIC_EXPORTS
)

# EXPORT_NAME формирует имя установленного target после NAMESPACE UniversalDevKit::.
set_target_properties(universaldevkit_diagnostic PROPERTIES
    EXPORT_NAME Diagnostic.Static
    POSITION_INDEPENDENT_CODE ON
)
set_target_properties(universaldevkit_diagnostic_dynamic PROPERTIES
    EXPORT_NAME Diagnostic.Dynamic
)

# Передаём родительскому файлу targets, которые должны попасть в install(EXPORT).
list(APPEND universaldevkit_component_targets
    universaldevkit_diagnostic
    universaldevkit_diagnostic_dynamic
)
set(universaldevkit_component_targets "${universaldevkit_component_targets}" PARENT_SCOPE)