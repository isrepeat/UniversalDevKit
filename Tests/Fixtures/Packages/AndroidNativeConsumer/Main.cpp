#include <Probe.h>

extern "C" __attribute__((visibility("default"))) int UdkConsumerValue() noexcept {
    return UdkPackageDeliveryValue();
}