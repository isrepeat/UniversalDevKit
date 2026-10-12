#include "../../Includes/UniversalDevKit/A/Value.h"

#include "../../Includes/UniversalDevKit/B/Value.h"
#include "../../Includes/UniversalDevKit/C/Value.h"

namespace udk_test {
    int ValueA() { return ValueB() + ValueC(); }
}