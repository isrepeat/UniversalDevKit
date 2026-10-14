cmake_minimum_required(VERSION 3.22)
project(UdkWinRtConsumer LANGUAGES CXX)
if(NOT WIN32 OR NOT UDK_PACKAGE_ROOT)
    message(FATAL_ERROR "Windows and UDK_PACKAGE_ROOT are required")
endif()
add_executable(consumer Main.cpp)
target_compile_features(consumer PRIVATE cxx_std_17)
target_include_directories(consumer PRIVATE "${UDK_PACKAGE_ROOT}/include")
target_link_libraries(consumer PRIVATE runtimeobject)
add_custom_command(TARGET consumer POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${UDK_PACKAGE_ROOT}/runtimes/win-x64/native/UdkWinRtProbe.dll"
    "$<TARGET_FILE_DIR:consumer>"
)