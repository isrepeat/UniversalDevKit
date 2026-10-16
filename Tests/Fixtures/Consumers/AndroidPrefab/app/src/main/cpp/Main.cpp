#include <jni.h>

#if !defined(UDK_TEST_HELPERS)
#include <UniversalDevKit/Diagnostic/Logging.h>
#if __has_include(<UniversalDevKit/Helpers/Text.h>)
#error Private Helpers headers leaked into Diagnostic consumer
#endif
#else
#include <UniversalDevKit/Helpers/Text.h>
#endif

extern "C" JNIEXPORT jint JNICALL Java_org_universaldevkit_packageconsumer_NativeBridge_verify(JNIEnv*, jclass) {
#if defined(UDK_TEST_HELPERS)
    return universaldevkit::text::EndsWithLineBreak("Android package\n") ? 0 : 1;
#else
    return universaldevkit::diagnostic::TryLog("Android Prefab consumer passed") ? 0 : 1;
#endif
}