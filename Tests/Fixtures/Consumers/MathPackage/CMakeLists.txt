cmake_minimum_required(VERSION 3.22)
project(UniversalDevKitMathConsumer LANGUAGES CXX)

find_package(UniversalDevKit CONFIG REQUIRED COMPONENTS Math)
add_executable(math_package Main.cpp)
target_link_libraries(math_package PRIVATE UniversalDevKit::Math.Headers)
enable_testing()
add_test(NAME MathPackage COMMAND math_package)