#include <UniversalDevKit/Diagnostic/Logging.h>
#include <UniversalDevKit/Helpers/Math.h>

#include <iostream>

int main() {
    static_assert(universaldevkit::math::Square(5) == 25);
    // Вызов реализации проверяет линковку, а не только доступность заголовков.
    if (!universaldevkit::math::IsPowerOfTwo(8)
        || universaldevkit::math::IsPowerOfTwo(7)) {
        return 1;
    }
    universaldevkit::diagnostic::Log("Diagnostic connected");
    std::cout << "App1 passed\n";
    return 0;
}