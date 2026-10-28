cmake_minimum_required(VERSION 3.22)
project(UniversalDevKitMetaPackageConsumer LANGUAGES CXX)

find_package(UniversalDevKit 0.1 CONFIG REQUIRED COMPONENTS Helpers)
add_executable(meta_package MetaPackage.cpp)
target_link_libraries(meta_package PRIVATE UniversalDevKit::Helpers.Headers)

enable_testing()
add_test(NAME MetaPackage COMMAND meta_package)

add_executable(meta_function_traits FunctionTraitsContract.cpp)
target_link_libraries(meta_function_traits PRIVATE UniversalDevKit::Helpers.Headers)
add_test(NAME MetaFunctionTraits COMMAND meta_function_traits)

add_executable(meta_command_line CommandLineMigration.cpp)
target_link_libraries(meta_command_line PRIVATE UniversalDevKit::Helpers.Headers)
add_test(NAME MetaCommandLineMigration COMMAND meta_command_line)