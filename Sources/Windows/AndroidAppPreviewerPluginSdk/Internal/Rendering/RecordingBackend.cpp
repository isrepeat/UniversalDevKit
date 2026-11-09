#include "Internal/Rendering/RecordingBackend.h"

#include <algorithm>
#include <cstring>

namespace universaldevkit::windows::androidapppreviewerpluginsdk::internal::rendering {
    using xaml::Rect;
    //
    // IRenderBackend
    //
    void RecordingBackend::BeginClip(const Rect& bounds) {
        this->Append(universaldevkit::windows::androidapppreviewerpluginsdk::xp_command_type_begin_clip, bounds);
    }

    void RecordingBackend::EndClip() {
        this->Append(universaldevkit::windows::androidapppreviewerpluginsdk::xp_command_type_end_clip, {});
    }

    void RecordingBackend::DrawOutline(const Rect& bounds, xaml::attr::Color color) {
        this->Append(universaldevkit::windows::androidapppreviewerpluginsdk::xp_command_type_outline, bounds, color);
    }

    void RecordingBackend::DrawRoundedRect(const Rect& bounds, xaml::attr::Color color, float cornerRadius) {
        this->Append(universaldevkit::windows::androidapppreviewerpluginsdk::xp_command_type_rounded_rect, bounds, color, cornerRadius);
    }

    void RecordingBackend::DrawRoundedRectOutline(
        const Rect& bounds,
        xaml::attr::Color color,
        float cornerRadius,
        float thickness) {
        universaldevkit::windows::androidapppreviewerpluginsdk::xp_command& command = this->Append(
            universaldevkit::windows::androidapppreviewerpluginsdk::xp_command_type_rounded_rect_outline,
            bounds,
            color,
            cornerRadius);
        std::memcpy(command.auxiliary, &thickness, sizeof(thickness));
    }

    void RecordingBackend::DrawShader(
        std::string_view,
        const Rect&,
        std::initializer_list<xaml::ShaderUniform>) {
    }

    void RecordingBackend::DrawText(
        const Rect& bounds,
        std::string_view text,
        xaml::attr::Color color,
        float fontSize,
        std::string_view fontWeight,
        xaml::attr::Alignment) {
        universaldevkit::windows::androidapppreviewerpluginsdk::xp_command& command = this->Append(
            universaldevkit::windows::androidapppreviewerpluginsdk::xp_command_type_text, bounds, color, fontSize);
        Copy(text, command.text, sizeof(command.text));
        Copy(fontWeight, command.auxiliary, sizeof(command.auxiliary));
    }

    void RecordingBackend::DrawImage(const Rect& bounds, std::string_view source, xaml::attr::Color tint) {
        universaldevkit::windows::androidapppreviewerpluginsdk::xp_command& command = this->Append(
            universaldevkit::windows::androidapppreviewerpluginsdk::xp_command_type_image, bounds, tint);
        Copy(source, command.text, sizeof(command.text));
    }

    //
    // Методы
    //
    const std::vector<universaldevkit::windows::androidapppreviewerpluginsdk::xp_command>& RecordingBackend::Commands() const {
        return this->commands;
    }

    //
    // Internal
    //
    universaldevkit::windows::androidapppreviewerpluginsdk::xp_command& RecordingBackend::Append(
        universaldevkit::windows::androidapppreviewerpluginsdk::xp_command_type type,
        const Rect& bounds,
        xaml::attr::Color color,
        float value) {
        this->commands.push_back({
            static_cast<int>(type),
            {bounds.x, bounds.y, bounds.width, bounds.height},
            {color.red, color.green, color.blue, color.alpha},
            value,
        });
        return this->commands.back();
    }

    void RecordingBackend::Copy(std::string_view source, char* destination, size_t capacity) {
        const size_t length = std::min(source.size(), capacity - 1);
        std::memcpy(destination, source.data(), length);
        destination[length] = '\0';
    }
}