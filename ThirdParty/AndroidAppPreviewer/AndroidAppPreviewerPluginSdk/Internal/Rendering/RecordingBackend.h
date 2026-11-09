#pragma once
#include <UniversalDevKit/XamlRuntime/RenderEngine.h>
#include <AndroidAppPreviewerPluginSdk/AndroidAppPreviewerPlugin.h>

#include <initializer_list>
#include <string_view>
#include <cstddef>
#include <vector>

namespace universaldevkit::windows::androidapppreviewerpluginsdk::internal::rendering {
    //
    // Собирает команды XAML-рендера в формат диагностики AndroidAppPreviewer.
    //
    class RecordingBackend final : public xaml::IRenderBackend {
    public:
        //
        // IRenderBackend
        //
        void BeginClip(const xaml::Rect& bounds) override;
        void EndClip() override;
        void DrawOutline(const xaml::Rect& bounds, xaml::attr::Color color) override;
        void DrawRoundedRect(const xaml::Rect& bounds, xaml::attr::Color color, float cornerRadius) override;
        void DrawRoundedRectOutline(
            const xaml::Rect& bounds,
            xaml::attr::Color color,
            float cornerRadius,
            float thickness) override;
        void DrawShader(
            std::string_view source,
            const xaml::Rect& bounds,
            std::initializer_list<xaml::ShaderUniform> uniforms) override;
        void DrawText(
            const xaml::Rect& bounds,
            std::string_view text,
            xaml::attr::Color color,
            float fontSize,
            std::string_view fontWeight,
            xaml::attr::Alignment alignment) override;
        void DrawImage(const xaml::Rect& bounds, std::string_view source, xaml::attr::Color tint) override;

        const std::vector<universaldevkit::windows::androidapppreviewerpluginsdk::xp_command>& Commands() const;

    private:
        universaldevkit::windows::androidapppreviewerpluginsdk::xp_command& Append(
            universaldevkit::windows::androidapppreviewerpluginsdk::xp_command_type type,
            const xaml::Rect& bounds,
            xaml::attr::Color color = {},
            float value = 0.0f);
        static void Copy(std::string_view source, char* destination, size_t capacity);

    private:
        std::vector<universaldevkit::windows::androidapppreviewerpluginsdk::xp_command> commands;
    };
}