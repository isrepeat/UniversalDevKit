#if !defined(UDK_TEST_HELEPRSTEST_ONLY)
#include <UniversalDevKit/DiagnosticTest/Logging.h>
#endif
#include <UniversalDevKit/HeleprsTest/Math.h>
#include <UniversalDevKit/HeleprsTest/Text.h>

int main() {
    static_assert(universaldevkit::heleprstest::math::Square(5) == 25);
    if (!universaldevkit::heleprstest::math::IsPowerOfTwo(8)
        || universaldevkit::heleprstest::math::IsPowerOfTwo(7)
        || !universaldevkit::heleprstest::text::EndsWithLineBreak("test\n")) {
        return 1;
    }
#if !defined(UDK_TEST_HELEPRSTEST_ONLY)
    universaldevkit::diagnostictest::Log("NuGet consumer connected");
    return universaldevkit::diagnostictest::TryLog("NuGet consumer passed") ? 0 : 2;
#else
    return 0;
#endif
}