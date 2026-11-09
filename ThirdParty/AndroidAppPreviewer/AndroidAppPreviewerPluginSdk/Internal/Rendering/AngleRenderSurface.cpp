#include "Internal/Rendering/AngleRenderSurface.h"

#include <GLES3/gl3.h>
#include <EGL/egl.h>

#include <UniversalDevKit/OpenGLESRenderer/OpenGlRenderer.h>
#include <UniversalDevKit/XamlRuntime/RenderEngine.h>
#include <UniversalDevKit/XamlRuntime/XamlLayout.h>

#include <filesystem>
#include <algorithm>
#include <stdexcept>
#include <iterator>
#include <fstream>
#include <memory>
#include <string>
#include <vector>

namespace universaldevkit::windows::androidapppreviewerpluginsdk::internal::rendering {
    namespace details {
        std::vector<unsigned char> ReadAllBytes(std::string_view path) {
            std::ifstream input(std::filesystem::path(path), std::ios::binary);
            if (!input) {
                throw std::runtime_error("Could not open resource: " + std::string(path));
            }
            return {std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>()};
        }

        EGLDisplay SharedDisplay() {
            // EGL display живёт до завершения процесса: выгрузка DLL не должна
            // вызывать eglTerminate после освобождения внутренних объектов ANGLE.
            static const EGLDisplay display = []() {
                EGLDisplay value = eglGetDisplay(EGL_DEFAULT_DISPLAY);
                if (value == EGL_NO_DISPLAY || eglInitialize(value, nullptr, nullptr) == EGL_FALSE) {
                    throw std::runtime_error("ANGLE could not initialize EGL");
                }
                return value;
            }();
            return display;
        }

    } // namespace details

    using xaml::Element;

    class AngleRenderSurface::Implementation {
    public:
        Implementation(
            int width,
            int height,
            std::string_view fontPath,
            std::string_view resourceRoot);
        ~Implementation();

        Implementation(const Implementation&) = delete;
        Implementation& operator=(const Implementation&) = delete;

        void Render(
            const std::function<void(xaml::IRenderBackend&)>& draw,
            unsigned char* destination,
            int destinationStride);

    private:
        int width;
        int height;
        EGLDisplay display = EGL_NO_DISPLAY;
        EGLSurface surface = EGL_NO_SURFACE;
        EGLContext context = EGL_NO_CONTEXT;
        std::unique_ptr<es_renderer::OpenGlRenderer> renderer;
    };

    AngleRenderSurface::Implementation::Implementation(
        int width,
        int height,
        std::string_view fontPath,
        std::string_view resourceRoot)
        : width(width)
        , height(height) {
        if (width <= 0 || height <= 0) {
            throw std::invalid_argument("ANGLE surface dimensions must be positive");
        }

        this->display = details::SharedDisplay();
        if (this->display == EGL_NO_DISPLAY
            || eglBindAPI(EGL_OPENGL_ES_API) == EGL_FALSE) {
            throw std::runtime_error("ANGLE could not initialize EGL");
        }

        const EGLint configurationAttributes[] = {
            EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
            EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
            EGL_RED_SIZE, 8,
            EGL_GREEN_SIZE, 8,
            EGL_BLUE_SIZE, 8,
            EGL_ALPHA_SIZE, 8,
            EGL_NONE,
        };

        EGLConfig configuration = nullptr;
        EGLint configurationCount = 0;

        if (eglChooseConfig(
            this->display,
            configurationAttributes,
            &configuration,
            1,
            &configurationCount) == EGL_FALSE
            || configurationCount == 0) {
            throw std::runtime_error("ANGLE could not choose a pbuffer configuration");
        }

        const EGLint surfaceAttributes[] = {
            EGL_WIDTH, this->width,
            EGL_HEIGHT, this->height,
            EGL_NONE,
        };
        this->surface = eglCreatePbufferSurface(this->display, configuration, surfaceAttributes);

        const EGLint contextAttributes[] = {
            EGL_CONTEXT_CLIENT_VERSION, 3,
            EGL_NONE,
        };

        this->context = eglCreateContext(
            this->display,
            configuration,
            EGL_NO_CONTEXT,
            contextAttributes);

        if (this->surface == EGL_NO_SURFACE
            || this->context == EGL_NO_CONTEXT
            || eglMakeCurrent(
                this->display,
                this->surface,
                this->surface,
                this->context) == EGL_FALSE) {
            throw std::runtime_error("ANGLE could not create an OpenGL ES 3 context");
        }

        const std::filesystem::path regularFontPath{std::string(fontPath)};
        const std::vector<unsigned char> regularFontData = details::ReadAllBytes(fontPath);
        const std::vector<unsigned char> boldFontData = details::ReadAllBytes(
            (regularFontPath.parent_path() / "Roboto-Bold.ttf").string()
        );
        const std::vector<unsigned char> blackFontData = details::ReadAllBytes(
            (regularFontPath.parent_path() / "Roboto-Black.ttf").string()
        );
        this->renderer = std::make_unique<es_renderer::OpenGlRenderer>(
            width,
            height,
            regularFontData.data(),
            regularFontData.size(),
            boldFontData.data(),
            boldFontData.size(),
            blackFontData.data(),
            blackFontData.size(),
            es_renderer::OpenGlRenderer::ShaderProgramSources{},
            [root = std::string(resourceRoot)](std::string_view source) {
                return details::ReadAllBytes(root + "/" + std::string(source));
            });
        xaml::SetTextGlyphMetrics(this->renderer->TextGlyphMetrics());
        if (eglMakeCurrent(
            this->display,
            EGL_NO_SURFACE,
            EGL_NO_SURFACE,
            EGL_NO_CONTEXT) == EGL_FALSE) {
            throw std::runtime_error("ANGLE could not release the offscreen context");
        }
    }

    AngleRenderSurface::Implementation::~Implementation() {
        if (this->display != EGL_NO_DISPLAY) {
            if (this->context != EGL_NO_CONTEXT && this->surface != EGL_NO_SURFACE) {
                eglMakeCurrent(this->display, this->surface, this->surface, this->context);
            }
            this->renderer.reset();
            eglMakeCurrent(this->display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
            if (this->context != EGL_NO_CONTEXT) {
                eglDestroyContext(this->display, this->context);
            }
            if (this->surface != EGL_NO_SURFACE) {
                eglDestroySurface(this->display, this->surface);
            }
        }
    }

    //
    // Реализация интерфейса
    //
    void AngleRenderSurface::Implementation::Render(
        const std::function<void(xaml::IRenderBackend&)>& draw,
        unsigned char* destination,
        int destinationStride) {
        if (destination == nullptr || destinationStride < this->width * 4) {
            throw std::invalid_argument("Invalid ANGLE render buffer arguments");
        }
        if (eglMakeCurrent(
            this->display,
            this->surface,
            this->surface,
            this->context) == EGL_FALSE) {
            throw std::runtime_error("ANGLE could not activate the offscreen context");
        }
        this->renderer->BeginFrame();
        glBlendFuncSeparate(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
        draw(*this->renderer);
        glFinish();

        std::vector<unsigned char> pixels(
            static_cast<size_t>(this->width) * static_cast<size_t>(this->height) * 4);
        glPixelStorei(GL_PACK_ALIGNMENT, 4);
        glReadPixels(
            0,
            0,
            this->width,
            this->height,
            GL_RGBA,
            GL_UNSIGNED_BYTE,
            pixels.data());
        for (int y = 0; y < this->height; ++y) {
            const unsigned char* source = pixels.data() + static_cast<size_t>(this->height - y - 1) * this->width * 4;
            unsigned char* row = destination + static_cast<size_t>(y) * destinationStride;
            for (int x = 0; x < this->width; ++x) {
                row[x * 4] = source[x * 4 + 2];
                row[x * 4 + 1] = source[x * 4 + 1];
                row[x * 4 + 2] = source[x * 4];
                row[x * 4 + 3] = source[x * 4 + 3];
            }
        }
        if (eglMakeCurrent(
            this->display,
            EGL_NO_SURFACE,
            EGL_NO_SURFACE,
            EGL_NO_CONTEXT) == EGL_FALSE) {
            throw std::runtime_error("ANGLE could not release the offscreen context");
        }
    }

    AngleRenderSurface::AngleRenderSurface(
        int width,
        int height,
        std::string_view fontPath,
        std::string_view resourceRoot)
        : implementation(std::make_unique<Implementation>(width, height, fontPath, resourceRoot)) {
    }

    AngleRenderSurface::~AngleRenderSurface() {

    }

    //
    // Методы
    //
    void AngleRenderSurface::Render(
        Element& root,
        unsigned char* destination,
        int destinationStride) {
        this->Render([&root](xaml::IRenderBackend& renderer) {
            xaml::Render(root, renderer);
        }, destination, destinationStride);
    }

    void AngleRenderSurface::Render(
        const std::function<void(xaml::IRenderBackend&)>& draw,
        unsigned char* destination,
        int destinationStride) {
        this->implementation->Render(draw, destination, destinationStride);
    }
}