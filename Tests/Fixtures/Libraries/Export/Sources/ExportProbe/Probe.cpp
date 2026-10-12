#include "../../Includes/UniversalDevKit/ExportProbe/Probe.h"

// Внутренняя функция имеет внешнее связывание, но не входит в публичный экспорт.
extern "C" UNIVERSALDEVKIT_API_LOCAL int UdkInternalProbe() {
    return 42;
}

extern "C" int UdkPublicProbe() {
    return UdkInternalProbe();
}