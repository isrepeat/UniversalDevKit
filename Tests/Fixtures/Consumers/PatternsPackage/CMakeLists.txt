cmake_minimum_required(VERSION 3.22)
project(UniversalDevKitPatternsConsumer LANGUAGES CXX)

add_subdirectory("${CMAKE_CURRENT_LIST_DIR}/../../../.." udk)
find_package(Threads REQUIRED)
add_executable(patterns_package Main.cpp)
target_link_libraries(patterns_package PRIVATE UniversalDevKit::Helpers.Headers Threads::Threads)

enable_testing()
add_test(NAME PatternsPackage COMMAND patterns_package)