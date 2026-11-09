#include <UniversalDevKit/ExportProbe/Probe.h>

int main() {
    return ::UdkPublicProbe() == 42 ? 0 : 1;
}