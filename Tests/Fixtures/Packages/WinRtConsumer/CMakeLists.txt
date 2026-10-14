cmake_minimum_required(VERSION 3.22)
project(UdkWinRtConsumer LANGUAGES CXX)
if(NOT WIN32 OR NOT UDK_PACKAGE_ROOT)
    message(FATAL_ERROR "Windows and UDK_PACKAGE_ROOT are required")
endif()
include("${UDK_PACKAGE_ROOT}/build/native/WindowsSdk.cmake")
set(projectionDirectory "${CMAKE_CURRENT_BINARY_DIR}/projection")
add_custom_command(OUTPUT "${projectionDirectory}/winrt/UniversalDevKit.TestPackages.h"
    COMMAND "${winrtSdkBin}/cppwinrt.exe"
        -input "${UDK_PACKAGE_ROOT}/winmd/UniversalDevKit.TestPackages.winmd"
        -input "${winrtWindowsMetadata}" -output "${projectionDirectory}"
    DEPENDS "${UDK_PACKAGE_ROOT}/winmd/UniversalDevKit.TestPackages.winmd"
    VERBATIM
)
add_executable(consumer Main.cpp app.manifest "${projectionDirectory}/winrt/UniversalDevKit.TestPackages.h")
target_compile_features(consumer PRIVATE cxx_std_20)
target_include_directories(consumer PRIVATE "${projectionDirectory}")
target_link_libraries(consumer PRIVATE runtimeobject)
add_custom_command(TARGET consumer POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${UDK_PACKAGE_ROOT}/runtimes/win-x64/native/UdkWinRtProbe.dll"
    "$<TARGET_FILE_DIR:consumer>"
)