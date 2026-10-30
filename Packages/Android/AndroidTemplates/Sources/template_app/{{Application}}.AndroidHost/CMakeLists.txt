add_library({{application}} SHARED
    Native.cpp
    AndroidCommandDispatcher.cpp
    AndroidCommandDispatcher.h
    Jni/Jni.cpp
    Jni/Jni.h)
target_compile_features({{application}} PRIVATE cxx_std_20)
target_include_directories({{application}} PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/..")
target_link_libraries({{application}} PRIVATE {{application}}_application UDK::Diagnostic android GLESv3)