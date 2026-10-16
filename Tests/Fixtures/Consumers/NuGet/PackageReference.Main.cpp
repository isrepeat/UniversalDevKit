#if !defined(UDK_TEST_HELPERS_ONLY)
#include <UniversalDevKit/Diagnostic/Logging.h>
#if defined(UDK_TEST_DYNAMIC) && !defined(UNIVERSALDEVKIT_DIAGNOSTIC_DYNAMIC)
#error Diagnostic dynamic import definition is missing
#endif
#if defined(UNIVERSALDEVKIT_HELPERS_DYNAMIC) || __has_include(<UniversalDevKit/Helpers/Text.h>)
#error Private Helpers requirements leaked into consumer
#endif
#else
#include <UniversalDevKit/Helpers/Text.h>
#if defined(UDK_TEST_DYNAMIC) && !defined(UNIVERSALDEVKIT_HELPERS_DYNAMIC)
#error Helpers dynamic import definition is missing
#endif
#endif

#include <iostream>

int main() {
#if defined(UDK_TEST_HELPERS_ONLY)
    if (!universaldevkit::text::EndsWithLineBreak("test\n")) { return 1; }
#else
    if (!universaldevkit::diagnostic::TryLog("PackageReference consumer passed")) { return 1; }
#endif
    std::cout << "PackageReference consumer passed\n";
    return 0;
}