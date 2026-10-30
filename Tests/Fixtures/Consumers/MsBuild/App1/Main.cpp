#include <UniversalDevKit/DiagnosticTest/Logging.h>
#include <UniversalDevKit/HeleprsTest/Math.h>

#include <iostream>

int main() {
    static_assert(universaldevkit::heleprstest::math::Square(5) == 25);
    // Вызов реализации проверяет линковку, а не только доступность заголовков.
    if (!universaldevkit::heleprstest::math::IsPowerOfTwo(8)
        || universaldevkit::heleprstest::math::IsPowerOfTwo(7)) {
        return 1;
    }
    universaldevkit::diagnostictest::Log("DiagnosticTest connected");
    std::cout << "App1 passed\n";
    return 0;
}