#if defined(UDK_TEST_MIXED_RUNTIME)
#include <UniversalDevKit/Diagnostic/Logging.h>
#include <UniversalDevKit/Helpers/Math.h>

#endif
#include <iostream>

int main() {
#if defined(UDK_TEST_MIXED_RUNTIME)
    // Проверяем обе реализации, собранные с CRT второго consumer.
    if (!universaldevkit::math::IsPowerOfTwo(8)) { return 1; }
    universaldevkit::diagnostic::Log("App2 Diagnostic connected");
#endif
    std::cout << "App2 passed\n";
    return 0;
}