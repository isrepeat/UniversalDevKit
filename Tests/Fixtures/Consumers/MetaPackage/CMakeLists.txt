cmake_minimum_required(VERSION 3.22)
project(UniversalDevKitMetaPackageConsumer LANGUAGES CXX)

find_package(UniversalDevKit 0.1 CONFIG REQUIRED COMPONENTS Meta)
add_executable(meta_package MetaPackage.cpp)
target_link_libraries(meta_package PRIVATE UniversalDevKit::Meta.Headers)

enable_testing()
add_test(NAME MetaPackage COMMAND meta_package)