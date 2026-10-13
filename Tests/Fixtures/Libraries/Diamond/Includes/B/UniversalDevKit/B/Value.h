#pragma once
#if defined(_WIN32) && defined(UNIVERSALDEVKIT_B_DYNAMIC)
#if defined(UNIVERSALDEVKIT_B_EXPORTS)
#define UDK_TEST_B_API __declspec(dllexport)
#else
#define UDK_TEST_B_API __declspec(dllimport)
#endif
#else
#define UDK_TEST_B_API
#endif

namespace udk_test {
    UDK_TEST_B_API int ValueB();
}