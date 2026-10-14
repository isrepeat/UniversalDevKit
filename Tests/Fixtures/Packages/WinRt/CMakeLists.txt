cmake_minimum_required(VERSION 3.22)
project(UdkWinRtPackageDelivery LANGUAGES CXX)
if(NOT WIN32)
    message(FATAL_ERROR "Windows is required")
endif()
include(WindowsSdk.cmake)
set(probeMetadata "${CMAKE_CURRENT_BINARY_DIR}/UniversalDevKit.TestPackages.winmd")
file(TO_NATIVE_PATH "${CMAKE_CURRENT_BINARY_DIR}" metadataOutputDirectory)
add_custom_command(OUTPUT "${probeMetadata}"
    COMMAND "${winrtSdkBin}/midlrt.exe" /winrt /nomidl /ns_prefix
        /I "${winrtSdkInclude}/winrt" /I "${winrtSdkInclude}/um" /I "${winrtSdkInclude}/shared"
        /metadata_dir "${winrtMetadataDirectory}"
        /reference "${winrtWindowsMetadata}"
        /winmd UniversalDevKit.TestPackages.winmd /h ProbeAbi.h
        /out "${metadataOutputDirectory}" Probe.idl
    DEPENDS Probe.idl
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    VERBATIM
)
add_custom_target(ProbeMetadata ALL DEPENDS "${probeMetadata}")
add_library(UdkWinRtProbe SHARED Probe.cpp Probe.def)
target_compile_features(UdkWinRtProbe PRIVATE cxx_std_17)
target_link_libraries(UdkWinRtProbe PRIVATE runtimeobject)
add_executable(UdkHostProbe Host.cpp)
install(TARGETS UdkWinRtProbe RUNTIME DESTINATION runtimes/win-x64/native)
install(TARGETS UdkHostProbe RUNTIME DESTINATION tools/win-x64)
install(FILES Probe.h DESTINATION include)
install(FILES "${probeMetadata}" DESTINATION winmd)
install(FILES WindowsSdk.cmake DESTINATION build/native)