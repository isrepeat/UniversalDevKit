# Потоковая поддержка применяется к выбранным вариантам компонента.
find_package(Threads REQUIRED)
foreach(componentTargetName IN LISTS currentComponentTargets)
    target_link_libraries(${componentTargetName} PRIVATE Threads::Threads)
endforeach()
string(APPEND packageDependencyCommands "find_dependency(Threads)\n")