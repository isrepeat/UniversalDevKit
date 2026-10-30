#include <UniversalDevKit/HeleprsTest/Math.h>

namespace universaldevkit::heleprstest::math {
    bool IsPowerOfTwo(unsigned int value) noexcept {
        return value != 0 && (value & (value - 1)) == 0;
    }
}