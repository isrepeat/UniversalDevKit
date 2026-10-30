#include "AndroidCommandDispatcher.h"

#if defined(__ANDROID__)
namespace {{application}}::android_host {
    AndroidCommandDispatcher::AndroidCommandDispatcher(JNIEnv* environment, jobject target)
        : target(environment, target)
        , dispatch(this->target.GetMethod<void(jint, jni::Utf8Bytes, jni::Utf8Bytes)>("dispatch")) {
    }

    //
    // API
    //
    void AndroidCommandDispatcher::Dispatch(
        application::core::HostCommand hostCommand,
        const application::core::HostCommandData& hostCommandData) const {
        this->dispatch.Call(
            this->target,
            static_cast<jint>(hostCommand),
            hostCommandData.value,
            hostCommandData.additionalValue
        );
    }
}
#endif