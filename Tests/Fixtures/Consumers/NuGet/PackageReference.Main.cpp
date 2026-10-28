#if defined(UDK_TEST_HEADER_HELPERS)
#include <UniversalDevKit/Helpers/Math/Tensor.h>
#include <UniversalDevKit/Helpers/Meta/Utilities/ValueExtractor.h>
#elif !defined(UDK_TEST_HELEPRSTEST_ONLY)
#include <UniversalDevKit/DiagnosticTest/Logging.h>
#if defined(UDK_TEST_DYNAMIC) && !defined(UNIVERSALDEVKIT_DIAGNOSTICTEST_DYNAMIC)
#error DiagnosticTest dynamic import definition is missing
#endif
#if defined(UNIVERSALDEVKIT_HELEPRSTEST_DYNAMIC) || __has_include(<UniversalDevKit/HeleprsTest/Text.h>)
#error Private HeleprsTest requirements leaked into consumer
#endif
#else
#include <UniversalDevKit/HeleprsTest/Text.h>
#if defined(UDK_TEST_DYNAMIC) && !defined(UNIVERSALDEVKIT_HELEPRSTEST_DYNAMIC)
#error HeleprsTest dynamic import definition is missing
#endif
#endif

#include <iostream>

int main() {
#if defined(UDK_TEST_HEADER_HELPERS)
    universaldevkit::helpers::math::Mat2x2f matrix;
    matrix[1][1] = 42.0f;
    float* value = &matrix[1][1];
    if (universaldevkit::helpers::meta::utilities::ValueExtractor::From(value) != 42.0f) { return 1; }
#elif defined(UDK_TEST_HELEPRSTEST_ONLY)
    if (!universaldevkit::heleprstest::text::EndsWithLineBreak("test\n")) { return 1; }
#else
    if (!universaldevkit::diagnostictest::TryLog("PackageReference consumer passed")) { return 1; }
#endif
    std::cout << "PackageReference consumer passed\n";
    return 0;
}