#include <UniversalDevKit/C/Value.h>

#include <iostream>

int main() {
    if (udk_test::ValueC() != 4) { return 1; }
    std::cout << "App2 passed\n";
    return 0;
}