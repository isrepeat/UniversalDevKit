# Компонент Helpers сам описывает варианты библиотеки и единый набор исходников.
set(universaldevkit_helpers_sources
    "${CMAKE_CURRENT_LIST_DIR}/../../../Sources/Helpers/Math.cpp"
)

# Настоящие targets используют внутренние имена; потребители выбирают явный вариант.
add_library(universaldevkit_helpers STATIC ${universaldevkit_helpers_sources})
add_library(universaldevkit_helpers_dynamic SHARED ${universaldevkit_helpers_sources})
add_library(UniversalDevKit::Helpers.Static ALIAS universaldevkit_helpers)
add_library(UniversalDevKit::Helpers.Dynamic ALIAS universaldevkit_helpers_dynamic)

target_link_libraries(universaldevkit_helpers PUBLIC UniversalDevKit::Headers)
target_link_libraries(universaldevkit_helpers_dynamic PUBLIC UniversalDevKit::Headers)
target_compile_definitions(universaldevkit_helpers_dynamic
    PUBLIC UNIVERSALDEVKIT_HELPERS_DYNAMIC
    PRIVATE UNIVERSALDEVKIT_HELPERS_EXPORTS
)

# EXPORT_NAME формирует имя установленного target после NAMESPACE UniversalDevKit::.
set_target_properties(universaldevkit_helpers PROPERTIES
    EXPORT_NAME Helpers.Static
    POSITION_INDEPENDENT_CODE ON
)
set_target_properties(universaldevkit_helpers_dynamic PROPERTIES
    EXPORT_NAME Helpers.Dynamic
)

# Передаём родительскому файлу targets, которые должны попасть в install(EXPORT).
list(APPEND universaldevkit_component_targets
    universaldevkit_helpers
    universaldevkit_helpers_dynamic
)
set(universaldevkit_component_targets "${universaldevkit_component_targets}" PARENT_SCOPE)