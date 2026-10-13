#pragma once
#if defined(_WIN32) && defined(UNIVERSALDEVKIT_A_DYNAMIC)
#if defined(UNIVERSALDEVKIT_A_EXPORTS)
#define UDK_TEST_A_API __declspec(dllexport)
#else
#define UDK_TEST_A_API __declspec(dllimport)
#endif
#else
#define UDK_TEST_A_API
#endif

namespace udk_test {
    UDK_TEST_A_API int ValueA();
}