#pragma once
#if defined(__ANDROID__)
#include <jni.h>

#include <type_traits>
#include <string_view>
#include <stdexcept>
#include <utility>
#include <memory>
#include <string>
#include <array>

namespace {{application}}::android_host::jni {
    // Маркеры явно различают Kotlin String (UTF-16) и ByteArray (UTF-8).
    struct String final {};
    struct Utf8Bytes final {};

    void Check(JNIEnv* environment, const std::string& operation);

    class Environment final {
    public:
        explicit Environment(JavaVM* vm);
        ~Environment();
        Environment(const Environment&) = delete;
        Environment& operator=(const Environment&) = delete;
        JNIEnv* Get() const;

    private:
        JavaVM* vm;
        JNIEnv* environment = nullptr;
        bool attached = false;
    };

    template <typename T>
    class LocalRef final {
    public:
        LocalRef(JNIEnv* environment, T value)
            : environment(environment)
            , value(value) {
        }
        ~LocalRef() {
            if (this->value != nullptr) {
                this->environment->DeleteLocalRef(this->value);
            }
        }
        LocalRef(const LocalRef&) = delete;
        LocalRef& operator=(const LocalRef&) = delete;
        T Get() const {
            return this->value;
        }

    private:
        JNIEnv* environment;
        T value;
    };

    class LocalFrame final {
    public:
        explicit LocalFrame(JNIEnv* environment, jint capacity);
        ~LocalFrame();
        LocalFrame(const LocalFrame&) = delete;
        LocalFrame& operator=(const LocalFrame&) = delete;

    private:
        JNIEnv* environment;
    };

    // Единственный владелец global reference; методы удерживают его до завершения вызовов.
    class ObjectState final {
    public:
        ObjectState(JNIEnv* environment, jobject object);
        ~ObjectState();
        ObjectState(const ObjectState&) = delete;
        ObjectState& operator=(const ObjectState&) = delete;
        JavaVM* Vm() const;
        jobject Get() const;

    private:
        JavaVM* vm = nullptr;
        jobject object = nullptr;
    };

    template <typename T>
    struct TypeTraits {
        static_assert(!std::is_same_v<T, T>, "Unsupported JNI type");
    };

    template <> struct TypeTraits<void> {
        static constexpr const char* signature = "V";
    };
    template <> struct TypeTraits<bool> {
        using Argument = bool;
        static constexpr const char* signature = "Z";
        static jvalue Convert(JNIEnv* environment, Argument value);
    };
    template <> struct TypeTraits<jint> {
        using Argument = jint;
        static constexpr const char* signature = "I";
        static jvalue Convert(JNIEnv* environment, Argument value);
    };
    template <> struct TypeTraits<jlong> {
        using Argument = jlong;
        static constexpr const char* signature = "J";
        static jvalue Convert(JNIEnv* environment, Argument value);
    };
    template <> struct TypeTraits<String> {
        using Argument = std::u16string_view;
        static constexpr const char* signature = "Ljava/lang/String;";
        static jvalue Convert(JNIEnv* environment, Argument value);
    };
    template <> struct TypeTraits<Utf8Bytes> {
        using Argument = std::string_view;
        static constexpr const char* signature = "[B";
        static jvalue Convert(JNIEnv* environment, Argument value);
    };

    template <typename Signature> class Method;

    class Object final {
    public:
        Object(JNIEnv* environment, jobject object);
        ~Object() = default;
        Object(const Object&) = delete;
        Object& operator=(const Object&) = delete;
        Object(Object&& other) noexcept;
        Object& operator=(Object&& other) noexcept;

        template <typename Signature>
        Method<Signature> GetMethod(std::string_view name) const {
            if (!this->state) {
                throw std::logic_error("JNI object has been moved");
            }
            return Method<Signature>(this->state, name);
        }

    private:
        template <typename Signature> friend class Method;
        std::shared_ptr<ObjectState> state;
    };

    template <typename R, typename... Args>
    class Method<R(Args...)> final {
        static_assert(std::is_same_v<R, void> || std::is_same_v<R, bool> ||
            std::is_same_v<R, jint> || std::is_same_v<R, jlong>, "Unsupported JNI return type");
    public:
        R Call(const Object& target, typename TypeTraits<Args>::Argument... arguments) const {
            if (!this->state || target.state != this->state) {
                throw std::invalid_argument("JNI method belongs to a different object");
            }
            Environment environment(this->state->Vm());
            auto* env = environment.Get();
            Check(env, this->description + ": pending exception before call");
            LocalFrame frame(env, static_cast<jint>(sizeof...(Args) + 8));
            std::array<jvalue, sizeof...(Args)> values{TypeTraits<Args>::Convert(env, arguments)...};
            if constexpr (std::is_same_v<R, void>) {
                env->CallVoidMethodA(this->state->Get(), this->method, values.data());
                Check(env, this->description);
            } else {
                R result{};
                if constexpr (std::is_same_v<R, bool>) {
                    result = env->CallBooleanMethodA(this->state->Get(), this->method, values.data()) != JNI_FALSE;
                } else if constexpr (std::is_same_v<R, jint>) {
                    result = env->CallIntMethodA(this->state->Get(), this->method, values.data());
                } else if constexpr (std::is_same_v<R, jlong>) {
                    result = env->CallLongMethodA(this->state->Get(), this->method, values.data());
                }
                Check(env, this->description);
                return result;
            }
        }

    private:
        friend class Object;
        Method(std::shared_ptr<ObjectState> state, std::string_view name)
            : state(std::move(state)) {
            if (name.empty() || name.find('\0') != std::string_view::npos) {
                throw std::invalid_argument("JNI method name is empty or contains NUL");
            }
            const std::string signature = std::string("(") + (std::string{} + ... + TypeTraits<Args>::signature)
                + ")" + TypeTraits<R>::signature;
            this->description = std::string(name) + signature;
            Environment environment(this->state->Vm());
            auto* env = environment.Get();
            Check(env, this->description + ": pending exception before lookup");
            LocalRef<jclass> type(env, env->GetObjectClass(this->state->Get()));
            Check(env, this->description + ": GetObjectClass");
            if (type.Get() == nullptr) {
                throw std::runtime_error("JNI class unavailable: " + this->description);
            }
            this->method = env->GetMethodID(type.Get(), std::string(name).c_str(), signature.c_str());
            Check(env, this->description + ": GetMethodID");
            if (this->method == nullptr) {
                throw std::runtime_error("JNI method not found: " + this->description);
            }
        }

    private:
        std::shared_ptr<ObjectState> state;
        jmethodID method = nullptr;
        std::string description;
    };
}
#endif