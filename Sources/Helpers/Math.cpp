#include <UniversalDevKit/Helpers/Math.h>

namespace universaldevkit::math {
    bool IsPowerOfTwo(unsigned int value) noexcept {
        return value != 0 && (value & (value - 1)) == 0;
    }
}