#if defined(__ANDROID__)
#include <jni.h>
#endif

#if defined(__ANDROID__)
#include <UniversalDevKit/OpenGLESRenderer/OpenGlRenderer.h>
#endif

#include <UniversalDevKit/Diagnostic/Logging.h>

#include "../{{Application}}.Application/Core/ApplicationSession.h"
#include "./AndroidCommandDispatcher.h"

#include <filesystem>
#include <stdexcept>
#include <iterator>
#include <fstream>
#include <limits>
#include <utility>
#include <string>
#include <vector>
#include <memory>

namespace {{application}}::android_host {
    namespace details {
        struct NativeHost final {
            {{application}}::application::core::ApplicationSession session{};
    #if defined(__ANDROID__)
            std::unique_ptr<es_renderer::OpenGlRenderer> renderer;
            std::unique_ptr<{{application}}::android_host::AndroidCommandDispatcher> dispatcher;
    #endif
        };

    #if defined(__ANDROID__)
        NativeHost& Host(jlong handle) {
            if (handle == 0) {
                throw std::invalid_argument("Native session is required");
            }
            return *reinterpret_cast<NativeHost*>(handle);
        }

        void ReportError(JNIEnv* environment, const std::exception& error) {
            if (!environment->ExceptionCheck()) {
                const auto type = environment->FindClass("java/lang/IllegalStateException");
                if (type != nullptr) {
                    environment->ThrowNew(type, error.what());
                    environment->DeleteLocalRef(type);
                }
            }
        }

        std::vector<unsigned char> ReadFont() {
            std::ifstream stream("/system/fonts/Roboto-Regular.ttf", std::ios::binary);
            if (!stream) {
                throw std::runtime_error("System Roboto font is unavailable");
            }
            return {std::istreambuf_iterator<char>(stream), std::istreambuf_iterator<char>()};
        }

        std::string ReadString(JNIEnv* environment, jstring value) {
            if (value == nullptr) {
                throw std::invalid_argument("Java string is required");
            }
            const char* const characters = environment->GetStringUTFChars(value, nullptr);
            if (characters == nullptr) {
                throw std::runtime_error("Cannot read Java string");
            }
            const std::string result(characters);
            environment->ReleaseStringUTFChars(value, characters);
            return result;
        }

        void ConfigureLogging(JNIEnv* environment, jstring path) {
            const auto initialized = universaldevkit::diagnostic::Logger::Initialize({
                .filePath = std::filesystem::path(ReadString(environment, path)),
                .maxFileSize = std::numeric_limits<std::size_t>::max(),
                .maxFiles = 0,
            });
            if (!initialized) { throw std::runtime_error("Native logging initialization failed"); }
            universaldevkit::diagnostic::Logger::Log(universaldevkit::diagnostic::Level::Info, "{{Application}}.Android", std::source_location::current(), "Logging initialized");
        }
    #endif
    } // namespace details

    #if defined(__ANDROID__)
    extern "C" JNIEXPORT jlong JNICALL Java_{{JniPackage}}_MainPage_nativeCreate(JNIEnv* environment, jobject, jobject dispatcher) {
        try {
            auto host = std::make_unique<details::NativeHost>();
            host->dispatcher = std::make_unique<{{application}}::android_host::AndroidCommandDispatcher>(environment, dispatcher);
            host->session.Controller().SetHostEventHandler([target = host->dispatcher.get()](auto command, const auto& data) {
                target->Dispatch(command, data);
            });
            return reinterpret_cast<jlong>(host.release());
        } catch (const std::exception& error) {
            details::ReportError(environment, error);
            return 0;
        }
    }

    extern "C" JNIEXPORT void JNICALL Java_{{JniPackage}}_MainPage_nativeConfigureLogFile(JNIEnv* environment, jobject, jlong handle, jstring path) {
        try {
            details::Host(handle);
            details::ConfigureLogging(environment, path);
        } catch (const std::exception& error) {
            details::ReportError(environment, error);
        }
    }

    extern "C" JNIEXPORT void JNICALL Java_{{JniPackage}}_NativeDiagnostics_nativeLog(JNIEnv* environment, jobject, jstring message) {
        try {
            universaldevkit::diagnostic::Logger::Log(universaldevkit::diagnostic::Level::Info, "{{Application}}.Android", std::source_location::current(), "{}", details::ReadString(environment, message));
        } catch (const std::exception& error) {
            details::ReportError(environment, error);
        }
    }

    extern "C" JNIEXPORT void JNICALL Java_{{JniPackage}}_MainPage_nativeDestroy(JNIEnv*, jobject, jlong handle) {
        auto* host = reinterpret_cast<details::NativeHost*>(handle);
        if (host != nullptr) {
            universaldevkit::diagnostic::Logger::Flush();
            delete host;
        }
    }

    extern "C" JNIEXPORT void JNICALL Java_{{JniPackage}}_MainPage_nativeSurface(JNIEnv* environment, jobject, jlong handle, jint width, jint height) {
        try {
            auto& host = details::Host(handle);
            const auto font = details::ReadFont();
            host.renderer = std::make_unique<es_renderer::OpenGlRenderer>(width, height,
                font.data(), font.size(), font.data(), font.size(), font.data(), font.size(),
                es_renderer::OpenGlRenderer::ShaderProgramSources{}, es_renderer::OpenGlRenderer::ResourceLoader{});
            xaml::SetTextGlyphMetrics(host.renderer->TextGlyphMetrics());
            host.session.Initialize({static_cast<float>(width), static_cast<float>(height)});
        } catch (const std::exception& error) {
            details::ReportError(environment, error);
        }
    }

    extern "C" JNIEXPORT void JNICALL Java_{{JniPackage}}_MainPage_nativeReleaseSurface(JNIEnv* environment, jobject, jlong handle) {
        try {
            auto& host = details::Host(handle);
            host.session.CancelPointer();
            host.renderer.reset();
        } catch (const std::exception& error) {
            details::ReportError(environment, error);
        }
    }

    extern "C" JNIEXPORT void JNICALL Java_{{JniPackage}}_MainPage_nativeRender(JNIEnv* environment, jobject, jlong handle) {
        try {
            auto& host = details::Host(handle);
            if (host.renderer) {
                host.session.Update();
                host.renderer->BeginFrame();
                host.session.Render(*host.renderer);
            }
        } catch (const std::exception& error) {
            details::ReportError(environment, error);
        }
    }

    extern "C" JNIEXPORT void JNICALL Java_{{JniPackage}}_MainPage_nativePointer(JNIEnv* environment, jobject, jlong handle, jint action, jfloat x, jfloat y) {
        try {
            auto& host = details::Host(handle);
            if (!host.renderer) {
                return;
            }
            switch (action) {
            case 0: host.session.PointerDown(x, y); break;
            case 1: host.session.PointerUp(x, y); break;
            case 2: host.session.PointerMove(x, y); break;
            default: host.session.CancelPointer(); break;
            }
        } catch (const std::exception& error) {
            details::ReportError(environment, error);
        }
    }

    extern "C" JNIEXPORT jboolean JNICALL Java_{{JniPackage}}_MainPage_nativeBack(JNIEnv* environment, jobject, jlong handle) {
        try {
            return details::Host(handle).session.Pages().NavigateBack();
        } catch (const std::exception& error) {
            details::ReportError(environment, error);
            return false;
        }
    }

    extern "C" JNIEXPORT void JNICALL Java_{{JniPackage}}_MainPage_nativeSetStatus(JNIEnv* environment, jobject, jlong handle, jbyteArray value) {
        try {
            if (value == nullptr) {
                return;
            }
            std::string status(static_cast<size_t>(environment->GetArrayLength(value)), '\0');
            environment->GetByteArrayRegion(value, 0, static_cast<jsize>(status.size()), reinterpret_cast<jbyte*>(status.data()));
            if (!environment->ExceptionCheck()) {
                auto& host = details::Host(handle);
                universaldevkit::diagnostic::Logger::Log(universaldevkit::diagnostic::Level::Info, "{{Application}}.Status", std::source_location::current(), "{}", status);
                host.session.Controller().SetStatus(std::move(status));
            }
        } catch (const std::exception& error) {
            details::ReportError(environment, error);
        }
    }
    #endif
}