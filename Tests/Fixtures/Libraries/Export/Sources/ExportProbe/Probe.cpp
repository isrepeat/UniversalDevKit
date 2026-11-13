#include <UniversalDevKit/ExportProbe/Probe.h>

// The internal function has external linkage and stays outside the public exports.
extern "C" UNIVERSALDEVKIT_API_LOCAL int UdkInternalProbe() {
    return 42;
}

extern "C" int UdkPublicProbe() {
    return UdkInternalProbe();
}