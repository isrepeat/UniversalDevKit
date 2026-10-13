#include <UniversalDevKit/ExportProbe/Probe.h>

#include <iostream>

int main() {
    if (UdkPublicProbe() != 42) { return 1; }
    std::cout << "App1 passed\n";
    return 0;
}