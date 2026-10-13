#pragma once
#if defined(_WIN32) && defined(UNIVERSALDEVKIT_D_DYNAMIC)
#if defined(UNIVERSALDEVKIT_D_EXPORTS)
#define UDK_TEST_D_API __declspec(dllexport)
#else
#define UDK_TEST_D_API __declspec(dllimport)
#endif
#else
#define UDK_TEST_D_API
#endif

namespace udk_test {
    UDK_TEST_D_API int ValueD();
}