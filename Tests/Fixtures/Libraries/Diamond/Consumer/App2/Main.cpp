#include <UniversalDevKit/C/Value.h>

#if defined(DIAMOND_TEST_BOUNDARIES) && (defined(UNIVERSALDEVKIT_D_DYNAMIC) || (defined(DIAMOND_TEST_HEADER_ISOLATION) && __has_include(<UniversalDevKit/D/Value.h>)))
#error Private D header leaked into consumer
#endif

#include <iostream>

int main() {
    if (udk_test::ValueC() != 4) { return 1; }
    std::cout << "App2 passed\n";
    return 0;
}