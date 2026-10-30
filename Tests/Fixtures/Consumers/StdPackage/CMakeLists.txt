cmake_minimum_required(VERSION 3.22)
project(UniversalDevKitStdConsumer LANGUAGES CXX)

add_subdirectory("${CMAKE_CURRENT_LIST_DIR}/../../../.." udk)
add_executable(std_package Main.cpp)
target_link_libraries(std_package PRIVATE UniversalDevKit::Helpers.Headers)

enable_testing()
add_test(NAME StdPackage COMMAND std_package)

add_executable(std_contract Contract.cpp)
target_link_libraries(std_contract PRIVATE UniversalDevKit::Helpers.Headers)
add_test(NAME StdContract COMMAND std_contract)