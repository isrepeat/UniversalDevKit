#include "Jni.h"

#if defined(__ANDROID__)
#include <limits>
#include <cstdio>

namespace _details {
    template <typename TAttach>
    jint AttachJniThread(TAttach attach, JavaVM* vm, JNIEnv** environment) {
        // NDK принимает JNIEnv**, desktop JDK — void**.
        if constexpr (std::is_invocable_r_v<jint, TAttach, JavaVM*, JNIEnv**, void*>) {
            return attach(vm, environment, nullptr);
        } else {
            return attach(vm, reinterpret_cast<void**>(environment), nullptr);
        }
    }
}

namespace {{application}}::android_host::jni {
    void Check(JNIEnv* environment, const std::string& operation) {
        if (environment->ExceptionCheck()) {
            // Java stack trace остаётся в журнале; JNI-исключение переводится в C++.
            environment->ExceptionDescribe();
            environment->ExceptionClear();
            throw std::runtime_error("JNI failure: " + operation + "; see Java exception in logcat");
        }
    }

    Environment::Environment(JavaVM* vm)
        : vm(vm) {
        if (this->vm == nullptr) {
            throw std::invalid_argument("JavaVM is required");
        }
        const auto result = this->vm->GetEnv(reinterpret_cast<void**>(&this->environment), JNI_VERSION_1_6);
        if (result == JNI_EDETACHED) {
            if (_details::AttachJniThread(this->vm->functions->AttachCurrentThread, this->vm, &this->environment) != JNI_OK) {
                throw std::runtime_error("Could not attach thread to JavaVM");
            }
            this->attached = true;
        } else if (result != JNI_OK) {
            throw std::runtime_error("Could not get JNI environment");
        }
    }

    Environment::~Environment() {
        if (this->attached) {
            this->vm->DetachCurrentThread();
        }
    }

    //
    // API
    //
    JNIEnv* Environment::Get() const {
        return this->environment;
    }

    LocalFrame::LocalFrame(JNIEnv* environment, jint capacity)
        : environment(environment) {
        if (this->environment->PushLocalFrame(capacity) != JNI_OK) {
            Check(this->environment, "PushLocalFrame");
            throw std::runtime_error("Could not allocate JNI local frame");
        }
    }

    LocalFrame::~LocalFrame() {
        this->environment->PopLocalFrame(nullptr);
    }

    ObjectState::ObjectState(JNIEnv* environment, jobject object) {
        if (environment == nullptr || object == nullptr) {
            throw std::invalid_argument("JNI environment and object are required");
        }
        Check(environment, "Object: pending exception");
        if (environment->GetJavaVM(&this->vm) != JNI_OK) {
            throw std::runtime_error("Could not get JavaVM");
        }
        this->object = environment->NewGlobalRef(object);
        Check(environment, "NewGlobalRef");
        if (this->object == nullptr) {
            throw std::runtime_error("Could not retain JNI object");
        }
    }

    ObjectState::~ObjectState() {
        try {
            Environment environment(this->vm);
            environment.Get()->DeleteGlobalRef(this->object);
        } catch (...) {
            // Деструктор не выбрасывает исключения при недоступной JVM.
            std::fputs("Could not release JNI global reference: JavaVM unavailable\n", stderr);
        }
    }

    //
    // API
    //
    JavaVM* ObjectState::Vm() const {
        return this->vm;
    }

    jobject ObjectState::Get() const {
        return this->object;
    }

    jvalue TypeTraits<bool>::Convert(JNIEnv*, Argument value) {
        jvalue result{};
        result.z = value ? JNI_TRUE : JNI_FALSE;
        return result;
    }

    jvalue TypeTraits<jint>::Convert(JNIEnv*, Argument value) {
        jvalue result{};
        result.i = value;
        return result;
    }

    jvalue TypeTraits<jlong>::Convert(JNIEnv*, Argument value) {
        jvalue result{};
        result.j = value;
        return result;
    }

    jvalue TypeTraits<String>::Convert(JNIEnv* environment, Argument value) {
        if (value.size() > static_cast<size_t>(std::numeric_limits<jsize>::max())) {
            throw std::length_error("JNI String is too large");
        }
        // Копирование исключает aliasing между char16_t и jchar; суррогатные пары сохраняются.
        const std::basic_string<jchar> characters(value.begin(), value.end());
        jvalue result{};
        result.l = environment->NewString(characters.data(), static_cast<jsize>(characters.size()));
        Check(environment, "NewString");
        if (result.l == nullptr) {
            throw std::runtime_error("Could not allocate JNI String");
        }
        return result;
    }

    jvalue TypeTraits<Utf8Bytes>::Convert(JNIEnv* environment, Argument value) {
        if (value.size() > static_cast<size_t>(std::numeric_limits<jsize>::max())) {
            throw std::length_error("JNI ByteArray is too large");
        }
        const auto bytes = environment->NewByteArray(static_cast<jsize>(value.size()));
        Check(environment, "NewByteArray");
        if (bytes == nullptr) {
            throw std::runtime_error("Could not allocate JNI ByteArray");
        }
        if (!value.empty()) {
            environment->SetByteArrayRegion(bytes, 0, static_cast<jsize>(value.size()), reinterpret_cast<const jbyte*>(value.data()));
            Check(environment, "SetByteArrayRegion");
        }
        jvalue result{};
        result.l = bytes;
        return result;
    }

    Object::Object(JNIEnv* environment, jobject object)
        : state(std::make_shared<ObjectState>(environment, object)) {
    }

    Object::Object(Object&& other) noexcept = default;
    Object& Object::operator=(Object&& other) noexcept = default;
}
#endif