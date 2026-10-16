cmake_minimum_required(VERSION 3.22)
project(UdkPackageDeliveryAndroidConsumer LANGUAGES CXX)
if(NOT ANDROID OR NOT UDK_PACKAGE_ROOT)
    message(FATAL_ERROR "Android toolchain and UDK_PACKAGE_ROOT are required")
endif()
add_library(udk_packagedelivery STATIC IMPORTED)
set_target_properties(udk_packagedelivery PROPERTIES
    IMPORTED_LOCATION "${UDK_PACKAGE_ROOT}/native/lib/${ANDROID_ABI}/libudk_packagedelivery.a"
    INTERFACE_INCLUDE_DIRECTORIES "${UDK_PACKAGE_ROOT}/native/include"
)
add_library(consumer SHARED Main.cpp)
target_link_libraries(consumer PRIVATE udk_packagedelivery)
target_link_options(consumer PRIVATE "-Wl,--no-undefined")