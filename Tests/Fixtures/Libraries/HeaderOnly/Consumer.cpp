#include <UniversalDevKit/HeaderProbe/Value.h>

int main() {
    static_assert(universaldevkit::headerprobe::Value() == 42);
    return 0;
}