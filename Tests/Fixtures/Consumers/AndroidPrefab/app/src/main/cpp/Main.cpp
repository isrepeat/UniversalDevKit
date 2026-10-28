#include <jni.h>

#if defined(UDK_TEST_META)
#include <UniversalDevKit/Meta/Utilities/ValueExtractor.h>
#include <UniversalDevKit/Meta/FunctionTraits.h>
#include <UniversalDevKit/Meta/Concepts.h>
#include <UniversalDevKit/Meta/Logic.h>
static_assert(universaldevkit::meta::concepts::Dereferenceable<int*>);
static_assert(!universaldevkit::meta::concepts::Dereferenceable<int>);
using MetaCallback = decltype([](int value) noexcept { return value; });
static_assert(universaldevkit::meta::FunctionTraits<MetaCallback>::IsNoexcept);
static_assert(universaldevkit::meta::FunctionTraits<MetaCallback>::ArgumentCount == 1);
static_assert(universaldevkit::meta::IF_value_c<true, 42, nullptr>::value == 42);
#elif !defined(UDK_TEST_HELPERS)
#include <UniversalDevKit/Diagnostic/Logging.h>
#if __has_include(<UniversalDevKit/Helpers/Text.h>)
#error Private Helpers headers leaked into Diagnostic consumer
#endif
#else
#include <UniversalDevKit/Helpers/Text.h>
#endif

extern "C" JNIEXPORT jint JNICALL Java_org_universaldevkit_packageconsumer_NativeBridge_verify(JNIEnv*, jclass) {
#if defined(UDK_TEST_META)
    int value = 42;
    int* pointer = &value;
    return universaldevkit::meta::utilities::ValueExtractor::From(pointer) == 42 ? 0 : 1;
#elif defined(UDK_TEST_HELPERS)
    return universaldevkit::text::EndsWithLineBreak("Android package\n") ? 0 : 1;
#else
    return universaldevkit::diagnostic::TryLog("Android Prefab consumer passed") ? 0 : 1;
#endif
}