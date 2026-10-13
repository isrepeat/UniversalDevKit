#include <UniversalDevKit/A/Value.h>

#include <iostream>

int main() {
    if (udk_test::ValueA() != 8) { return 1; }
    std::cout << "App1 passed\n";
    return 0;
}