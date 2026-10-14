#include <UniversalDevKit/A/Value.h>

#if defined(DIAMOND_TEST_BOUNDARIES)
#if DIAMOND_TEST_PUBLIC_B
#include <UniversalDevKit/B/Value.h>
#if defined(DIAMOND_TEST_DYNAMIC) && !defined(DIAMOND_TEST_PUBLIC_STATIC) && !defined(UNIVERSALDEVKIT_B_DYNAMIC)
#error Public dynamic B import definition is missing
#endif
#if defined(DIAMOND_TEST_PUBLIC_STATIC) && defined(UNIVERSALDEVKIT_B_DYNAMIC)
#error Static B received a dynamic import definition
#endif
#else
#if defined(UNIVERSALDEVKIT_B_DYNAMIC) || (defined(DIAMOND_TEST_HEADER_ISOLATION) && __has_include(<UniversalDevKit/B/Value.h>))
#error Private B requirements leaked into consumer
#endif
#endif
#if defined(UNIVERSALDEVKIT_C_DYNAMIC) || (defined(DIAMOND_TEST_HEADER_ISOLATION) && __has_include(<UniversalDevKit/C/Value.h>))
#error Private C header leaked into consumer
#endif
#endif

#include <iostream>

int main() {
    #if defined(DIAMOND_TEST_BOUNDARIES) && DIAMOND_TEST_PUBLIC_B
    if (udk_test::ValueB() != 4) { return 2; }
    #endif
    if (udk_test::ValueA() != 8) { return 1; }
    std::cout << "App1 passed\n";
    return 0;
}