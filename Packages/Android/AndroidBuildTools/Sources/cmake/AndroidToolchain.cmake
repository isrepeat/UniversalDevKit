# Выполняется до project(), включая проверки компилятора.
# Явно заданный CMAKE_ANDROID_NDK имеет приоритет.
set(CMAKE_SYSTEM_NAME Android)
if(NOT CMAKE_ANDROID_NDK)
    set(_android_build_tools_ndk_candidates "$ENV{ANDROID_NDK_HOME}" "$ENV{ANDROID_NDK_ROOT}")
    foreach(_android_build_tools_sdk "$ENV{ANDROID_SDK_ROOT}" "$ENV{ANDROID_HOME}" "$ENV{LOCALAPPDATA}/Android/Sdk")
        file(GLOB _android_build_tools_sdk_ndks LIST_DIRECTORIES true "${_android_build_tools_sdk}/ndk/*")
        list(SORT _android_build_tools_sdk_ndks COMPARE NATURAL ORDER DESCENDING)
        list(APPEND _android_build_tools_ndk_candidates ${_android_build_tools_sdk_ndks})
    endforeach()
    file(GLOB _android_build_tools_vs_ndks LIST_DIRECTORIES true
        "$ENV{ProgramFiles}/Android/AndroidNDK/*"
        "$ENV{ProgramFiles} (x86)/Android/AndroidNDK/*")
    list(SORT _android_build_tools_vs_ndks COMPARE NATURAL ORDER DESCENDING)
    list(APPEND _android_build_tools_ndk_candidates ${_android_build_tools_vs_ndks})
    foreach(_android_build_tools_ndk IN LISTS _android_build_tools_ndk_candidates)
        if(EXISTS "${_android_build_tools_ndk}/source.properties" AND
           EXISTS "${_android_build_tools_ndk}/toolchains/llvm/prebuilt/windows-x86_64/bin/clang.exe")
            file(TO_CMAKE_PATH "${_android_build_tools_ndk}" CMAKE_ANDROID_NDK)
            set(CMAKE_ANDROID_NDK "${CMAKE_ANDROID_NDK}" CACHE PATH "Android NDK installation")
            break()
        endif()
    endforeach()
endif()
if(NOT EXISTS "${CMAKE_ANDROID_NDK}/source.properties")
    message(FATAL_ERROR "Android NDK was not found. Install the NDK or set ANDROID_NDK_HOME / CMAKE_ANDROID_NDK to its directory.")
endif()