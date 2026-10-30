#include <jni.h>

#if defined(UDK_TEST_DIAGNOSTIC)
#include <UniversalDevKit/Diagnostic/Logging.h>
#if !defined(UNIVERSALDEVKIT_DIAGNOSTIC_DYNAMIC)
#error Diagnostic dynamic import definition is missing
#endif
#if __has_include(<UniversalDevKit/Helpers/System/Thread.h>) || __has_include(<spdlog/spdlog.h>)
#error Private logger dependencies leaked into consumer
#endif
#elif defined(UDK_TEST_HELPERS)
#include <UniversalDevKit/Helpers/Meta/Utilities/ValueExtractor.h>
#include <UniversalDevKit/Helpers/Meta/FunctionTraits.h>
#include <UniversalDevKit/Helpers/Math/Differentiation.h>
#include <UniversalDevKit/Helpers/Math/Function1D.h>
#include <UniversalDevKit/Helpers/Math/Tensor.h>
#include <UniversalDevKit/Helpers/Math/Rect.h>
#include <UniversalDevKit/Helpers/Math/Size.h>
using Callback = decltype([](int value) noexcept { return value; });
static_assert(universaldevkit::helpers::meta::FunctionTraits<Callback>::IsNoexcept);
#elif defined(UDK_TEST_HELEPRSTEST)
#include <UniversalDevKit/HeleprsTest/Text.h>
#else
#include <UniversalDevKit/DiagnosticTest/Logging.h>
#if __has_include(<UniversalDevKit/HeleprsTest/Text.h>)
#error Private HeleprsTest headers leaked into DiagnosticTest consumer
#endif
#endif

extern "C" JNIEXPORT jint JNICALL Java_org_universaldevkit_packageconsumer_NativeBridge_verify(JNIEnv*, jclass) {
#if defined(UDK_TEST_DIAGNOSTIC)
    using universaldevkit::diagnostic::Logger;
    if (!Logger::Initialize()) { return 1; }
    const bool enabled = Logger::ShouldLog(universaldevkit::diagnostic::Level::Info);
    Logger::Write(universaldevkit::diagnostic::Level::Info, "Package", "Android Diagnostic package passed");
    Logger::Shutdown();
    return enabled ? 0 : 2;
#elif defined(UDK_TEST_HELPERS)
    universaldevkit::helpers::math::Mat2x2f matrix;
    matrix[1][1] = 7.0f;
    matrix[1][1] += 1.0f;
    float* value = &matrix[1][1];
    return universaldevkit::helpers::meta::utilities::ValueExtractor::From(value) == 8.0f ? 0 : 1;
#elif defined(UDK_TEST_HELEPRSTEST)
    return universaldevkit::heleprstest::text::EndsWithLineBreak("Android package\n") ? 0 : 1;
#else
    return universaldevkit::diagnostictest::TryLog("Android Prefab consumer passed") ? 0 : 1;
#endif
}