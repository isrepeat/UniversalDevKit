#pragma once
#if defined(__ANDROID__)
#include "../{{Application}}.Application/Interface/IHostCommandDispatcher.h"
#include "./Jni/Jni.h"

namespace {{application}}::android_host {
    class AndroidCommandDispatcher final {
    public:
        AndroidCommandDispatcher(JNIEnv* environment, jobject target);
        ~AndroidCommandDispatcher() = default;
        AndroidCommandDispatcher(const AndroidCommandDispatcher&) = delete;
        AndroidCommandDispatcher& operator=(const AndroidCommandDispatcher&) = delete;
        void Dispatch(
            application::core::HostCommand hostCommand,
            const application::core::HostCommandData& hostCommandData) const;

    private:
        jni::Object target;
        jni::Method<void(jint, jni::Utf8Bytes, jni::Utf8Bytes)> dispatch;
    };
}
#endif