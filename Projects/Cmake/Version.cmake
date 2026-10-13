# Единый источник версии выпуска и поколения ABI.
file(READ "${CMAKE_CURRENT_LIST_DIR}/../../Version.json" udkVersionDescription)
string(JSON udkReleaseVersion GET "${udkVersionDescription}" version)
string(JSON udkAbiVersion GET "${udkVersionDescription}" abiVersion)
if(NOT udkReleaseVersion MATCHES "^[0-9]+\\.[0-9]+\\.[0-9]+$" OR NOT udkAbiVersion MATCHES "^[0-9]+$")
    message(FATAL_ERROR "Invalid UniversalDevKit Version.json")
endif()
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${CMAKE_CURRENT_LIST_DIR}/../../Version.json")