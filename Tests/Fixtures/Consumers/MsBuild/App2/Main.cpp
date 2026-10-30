#if defined(UDK_TEST_MIXED_RUNTIME)
#include <UniversalDevKit/DiagnosticTest/Logging.h>
#include <UniversalDevKit/HeleprsTest/Math.h>

#endif
#include <iostream>

int main() {
#if defined(UDK_TEST_MIXED_RUNTIME)
    // Проверяем обе реализации, собранные с CRT второго consumer.
    if (!universaldevkit::heleprstest::math::IsPowerOfTwo(8)) { return 1; }
    universaldevkit::diagnostictest::Log("App2 DiagnosticTest connected");
#endif
    std::cout << "App2 passed\n";
    return 0;
}