#pragma once
#if defined(_WIN32) && defined(UNIVERSALDEVKIT_C_DYNAMIC)
#if defined(UNIVERSALDEVKIT_C_EXPORTS)
#define UDK_TEST_C_API __declspec(dllexport)
#else
#define UDK_TEST_C_API __declspec(dllimport)
#endif
#else
#define UDK_TEST_C_API
#endif

namespace udk_test {
    UDK_TEST_C_API int ValueC();
}