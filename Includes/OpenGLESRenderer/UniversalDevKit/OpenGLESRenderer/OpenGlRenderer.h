#pragma once
#include <UniversalDevKit/XamlRuntime/RenderEngine.h>

#include "Config.h"
#include "Export.h"

#include <unordered_map>
#include <functional>
#include <cstddef>
#include <memory>
#include <string>
#include <vector>

namespace universaldevkit::openglesrenderer {
    class UNIVERSALDEVKIT_OPENGLESRENDERER_API OpenGlRenderer final : public xaml::IRenderBackend {
    public:
        using ResourceLoader = std::function<std::vector<unsigned char>(std::string_view)>;

        struct ShaderProgramSource {
            std::string_view vertex;
            std::string_view fragment;
        };
        // Ключи для необязательной подмены стандартных программ библиотеки.
        struct ShaderRoles {
            static constexpr char text[] = "core.text";
            static constexpr char solid[] = "core.solid";
            static constexpr char roundedRectangle[] = "core.roundedRectangle";
            static constexpr char image[] = "core.image";
        };
        // Дополнительные программы хоста и явные подмены стандартных ролей.
        // Набор может быть пустым. Исходники должны жить до завершения конструктора.
        using ShaderProgramSources = std::unordered_map<std::string, ShaderProgramSource>;

        OpenGlRenderer(
            int width,
            int height,
            const unsigned char* regularFontData,
            size_t regularFontSize,
            const unsigned char* boldFontData,
            size_t boldFontSize,
            const unsigned char* blackFontData,
            size_t blackFontSize,
            ShaderProgramSources shaderPrograms,
            ResourceLoader resourceLoader);
        ~OpenGlRenderer();

        OpenGlRenderer(const OpenGlRenderer&) = delete;
        OpenGlRenderer& operator=(const OpenGlRenderer&) = delete;

        void BeginFrame();
        std::vector<xaml::TextGlyphMetric> TextGlyphMetrics() const;

    private:
        class Implementation;

    private:
        //
        // IRenderBackend
        //
        void BeginClip(const xaml::Rect& bounds) override;
        void EndClip() override;
        void DrawOutline(const xaml::Rect& bounds, xaml::attr::Color color) override;
        void DrawRoundedRect(
            const xaml::Rect& bounds,
            xaml::attr::Color color,
            float cornerRadius) override;
        void DrawRoundedRectOutline(
            const xaml::Rect& bounds,
            xaml::attr::Color color,
            float cornerRadius,
            float thickness) override;
        void DrawShader(
            std::string_view shaderName,
            const xaml::Rect& bounds,
            std::initializer_list<xaml::ShaderUniform> uniforms) override;
        void DrawText(
            const xaml::Rect& bounds,
            std::string_view text,
            xaml::attr::Color color,
            float fontSize,
            std::string_view fontWeight,
            xaml::attr::Alignment horizontalAlignment) override;
        void DrawImage(
            const xaml::Rect& bounds,
            std::string_view source,
            xaml::attr::Color tint) override;

    private:
        std::unique_ptr<Implementation> implementation;
    };
}