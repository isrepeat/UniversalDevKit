cmake_minimum_required(VERSION 3.22)
project(UniversalDevKitMathConsumer LANGUAGES CXX)

find_package(UniversalDevKit CONFIG REQUIRED COMPONENTS Helpers)
add_executable(math_package Main.cpp)
target_link_libraries(math_package PRIVATE UniversalDevKit::Helpers.Headers)
enable_testing()
add_test(NAME MathPackage COMMAND math_package)