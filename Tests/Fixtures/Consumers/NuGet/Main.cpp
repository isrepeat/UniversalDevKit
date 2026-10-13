#if !defined(UDK_TEST_HELPERS_ONLY)
#include <UniversalDevKit/Diagnostic/Logging.h>
#endif
#include <UniversalDevKit/Helpers/Math.h>
#include <UniversalDevKit/Helpers/Text.h>

int main() {
    static_assert(universaldevkit::math::Square(5) == 25);
    if (!universaldevkit::math::IsPowerOfTwo(8)
        || universaldevkit::math::IsPowerOfTwo(7)
        || !universaldevkit::text::EndsWithLineBreak("test\n")) {
        return 1;
    }
#if !defined(UDK_TEST_HELPERS_ONLY)
    universaldevkit::diagnostic::Log("NuGet consumer connected");
    return universaldevkit::diagnostic::TryLog("NuGet consumer passed") ? 0 : 2;
#else
    return 0;
#endif
}