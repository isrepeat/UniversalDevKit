#include "../../Includes/XamlRuntime/UniversalDevKit/XamlRuntime/RenderEngine.h"

#include <algorithm>
#include <cctype>
#include <vector>
#include <cmath>

namespace universaldevkit::xamlruntime::details {
    Rect Translate(Rect bounds, float offsetX, float offsetY = 0.0f) {
        return universaldevkit::helpers::math::Geometry::Translate(bounds, offsetX, offsetY);
    }

    attr::Color WithOpacity(attr::Color color, float opacity) {
        return universaldevkit::helpers::math::ColorMath::WithOpacity(color, opacity);
    }

    attr::Color InterpolateColor(attr::Color from, attr::Color to, float progress) {
        return universaldevkit::helpers::math::ColorMath::Interpolate(from, to, progress);
    }

    bool AreEqual(attr::Color left, attr::Color right) {
        return left == right;
    }

    attr::Color ButtonColor(
        const Element& element,
        attr::Color inactive,
        attr::Color active) {
        if (active.alpha <= 0.0f) {
            return inactive;
        }
        return InterpolateColor(inactive, active, element.PressProgress());
    }

    std::vector<std::string> WrapText(std::string_view text, float width, float fontSize) {
        const size_t maximumCharacters = std::max(
            static_cast<size_t>(1),
            static_cast<size_t>(width / (fontSize * 0.55f)));
        std::vector<std::string> lines;
        std::string line;
        std::string word;
        size_t lineLength = 0;
        size_t wordLength = 0;
        const auto addWord = [&] {
            if (word.empty()) {
                return;
            }
            if (!line.empty() && lineLength + 1 + wordLength > maximumCharacters) {
                lines.push_back(std::move(line));
                line.clear();
                lineLength = 0;
            }
            if (!line.empty()) {
                line += ' ';
                ++lineLength;
            }
            line += word;
            lineLength += wordLength;
            word.clear();
            wordLength = 0;
        };
        for (const unsigned char character : text) {
            if (std::isspace(character)) {
                addWord();
            } else {
                word += static_cast<char>(character);
                if ((character & 0xC0) != 0x80) {
                    ++wordLength;
                }
            }
        }
        addWord();
        if (!line.empty()) {
            lines.push_back(std::move(line));
        }
        return lines;
    }

    void RenderTextBlock(
        const Element& element,
        IRenderBackend& backend,
        Rect bounds,
        float opacity) {
        const std::vector<std::string> lines = element.TextWrapping()
            ? WrapText(element.Text(), bounds.width, element.FontSize())
            : std::vector<std::string>{element.Text()};
        const float lineHeight = lines.empty() ? bounds.height : bounds.height / static_cast<float>(lines.size());
        for (size_t index = 0; index < lines.size(); ++index) {
            Rect lineBounds = bounds;
            lineBounds.y += lineHeight * static_cast<float>(index);
            lineBounds.height = lineHeight;
            backend.DrawText(
                lineBounds,
                lines[index],
                WithOpacity(element.Foreground(), opacity),
                element.FontSize(),
                element.FontWeight(),
                element.HorizontalAlignmentValue());
        }
    }

    void RenderToggleSwitch(
        const Element& element,
        IRenderBackend& backend,
        Rect bounds,
        float opacity) {
        const float targetProgress = element.IsOn() ? 1.0f : 0.0f;
        const float progress = element.ToggleProgress() < 0.0f
            ? targetProgress : element.ToggleProgress();
        backend.DrawRoundedRect(
            bounds,
            WithOpacity(
                InterpolateColor(element.BorderColor(), element.Background(), progress),
                opacity),
            bounds.height / 2.0f);
        const float inset = 4.0f;
        const float thumbSize = std::max(0.0f, bounds.height - inset * 2.0f);
        const float thumbX = bounds.x + inset
            + (bounds.width - inset * 2.0f - thumbSize) * progress;
        backend.DrawRoundedRect(
            {thumbX, bounds.y + inset, thumbSize, thumbSize},
            WithOpacity(
                InterpolateColor(element.Tint(), element.Foreground(), progress),
                opacity),
            thumbSize / 2.0f);
    }

    void RenderSvgImage(const Element& element, IRenderBackend& backend) {
        backend.DrawImage(element.Bounds(), element.Source(), element.Tint());
    }

    void RenderChrome(
        const Element& element,
        IRenderBackend& backend,
        Rect bounds,
        float opacity) {
        if (element.Type() == ElementType::toggleSwitch) {
            return;
        }

        const attr::Color background = element.Type() == ElementType::button
            ? ButtonColor(element, element.Background(), element.ActiveBackground())
            : element.Background();
        const attr::Color borderColor = element.Type() == ElementType::button
            ? ButtonColor(element, element.BorderColor(), element.ActiveBorderColor())
            : element.BorderColor();
        const attr::Thickness borderThickness = element.BorderThickness();
        const float thickness = std::max({
            borderThickness.left,
            borderThickness.right,
            borderThickness.top,
            borderThickness.bottom,
        });
        if (thickness <= 0.0f) {
            backend.DrawRoundedRect(
                bounds,
                WithOpacity(background, opacity),
                element.CornerRadius());
            return;
        }
        if (background.alpha <= 0.0f) {
            backend.DrawRoundedRectOutline(
                bounds,
                WithOpacity(borderColor, opacity),
                element.CornerRadius(),
                thickness);
            return;
        }
        if (AreEqual(background, borderColor)) {
            backend.DrawRoundedRect(
                bounds,
                WithOpacity(background, opacity),
                element.CornerRadius());
            return;
        }

        backend.DrawRoundedRect(
            bounds,
            WithOpacity(borderColor, opacity),
            element.CornerRadius());
        const Rect innerBounds = universaldevkit::helpers::math::Geometry::Inset(bounds, borderThickness);
        backend.DrawRoundedRect(
            innerBounds,
            WithOpacity(background, opacity),
            std::max(0.0f, element.CornerRadius() - thickness));
    }

    void RenderElement(
        const Element& element,
        IRenderBackend& backend,
        const RendererRegistry* renderers,
        float inheritedOffsetX,
        float inheritedOffsetY,
        float inheritedOpacity);

    void RenderScrollBars(const Element& element, IRenderBackend& backend, Rect bounds, float opacity) {
        const Size extent = element.Extent();
        const Size viewport = element.Viewport();
        constexpr float thickness = 6.0f;
        const attr::Color track{0.0f, 0.0f, 0.0f, 0.20f};
        const attr::Color thumb{0.85f, 0.85f, 0.85f, 0.65f};
        const bool vertical = element.VerticalScrollBarVisibility() == attr::ScrollBarVisibility::visible
            || (element.VerticalScrollBarVisibility() == attr::ScrollBarVisibility::autoValue && extent.height > viewport.height);
        if (vertical && viewport.height > 0.0f) {
            const float thumbHeight = std::max(18.0f, viewport.height * viewport.height / extent.height);
            const float range = std::max(0.0f, viewport.height - thumbHeight);
            const float maximum = std::max(0.0f, extent.height - viewport.height);
            const float y = bounds.y + (maximum == 0.0f ? 0.0f : range * element.VerticalOffset() / maximum);
            backend.DrawRoundedRect({bounds.x + bounds.width - thickness, bounds.y, thickness, viewport.height}, WithOpacity(track, opacity), thickness / 2.0f);
            backend.DrawRoundedRect({bounds.x + bounds.width - thickness, y, thickness, thumbHeight}, WithOpacity(thumb, opacity), thickness / 2.0f);
        }
        const bool horizontal = element.HorizontalScrollBarVisibility() == attr::ScrollBarVisibility::visible
            || (element.HorizontalScrollBarVisibility() == attr::ScrollBarVisibility::autoValue && extent.width > viewport.width);
        if (horizontal && viewport.width > 0.0f) {
            const float thumbWidth = std::max(18.0f, viewport.width * viewport.width / extent.width);
            const float range = std::max(0.0f, viewport.width - thumbWidth);
            const float maximum = std::max(0.0f, extent.width - viewport.width);
            const float x = bounds.x + (maximum == 0.0f ? 0.0f : range * element.HorizontalOffset() / maximum);
            backend.DrawRoundedRect({bounds.x, bounds.y + bounds.height - thickness, viewport.width, thickness}, WithOpacity(track, opacity), thickness / 2.0f);
            backend.DrawRoundedRect({x, bounds.y + bounds.height - thickness, thumbWidth, thickness}, WithOpacity(thumb, opacity), thickness / 2.0f);
        }
    }

    void RenderWireframe(
        IRenderBackend& backend,
        const Rect& bounds,
        float opacity,
        float cornerRadius,
        const attr::Wireframe& wireframe) {
        if (wireframe.thickness <= 0.0f || wireframe.color.alpha <= 0.0f) {
            return;
        }

        const attr::Color color = WithOpacity(wireframe.color, opacity);
        if (wireframe.lineStyle == attr::WireframeLineStyle::solid) {
            backend.DrawRoundedRectOutline(bounds, color, cornerRadius, wireframe.thickness);
            return;
        }

        const float dashLength = wireframe.thickness * 3.0f;
        const float dashStep = dashLength * 2.0f;
        if (dashLength <= 0.0f) {
            return;
        }
        const auto drawDash = [&backend, color, &wireframe](const Rect& dashBounds) {
            backend.DrawRoundedRect(dashBounds, color, wireframe.thickness / 2.0f);
        };
        for (float x = bounds.x; x < bounds.x + bounds.width; x += dashStep) {
            const float width = std::min(dashLength, bounds.x + bounds.width - x);
            drawDash({x, bounds.y, width, wireframe.thickness});
            drawDash({x, bounds.y + bounds.height - wireframe.thickness, width, wireframe.thickness});
        }
        for (float y = bounds.y + dashStep; y < bounds.y + bounds.height - wireframe.thickness; y += dashStep) {
            const float height = std::min(dashLength, bounds.y + bounds.height - y);
            drawDash({bounds.x, y, wireframe.thickness, height});
            drawDash({bounds.x + bounds.width - wireframe.thickness, y, wireframe.thickness, height});
        }
    }

    void RenderWireframeInsets(
        IRenderBackend& backend,
        const Rect& bounds,
        const attr::Thickness& thickness,
        attr::Color color,
        float opacity) {
        if (color.alpha <= 0.0f) {
            return;
        }
        color = WithOpacity(color, opacity);
        backend.DrawRoundedRect({bounds.x, bounds.y, bounds.width, thickness.top}, color, 0.0f);
        backend.DrawRoundedRect({bounds.x, bounds.y + bounds.height - thickness.bottom, bounds.width, thickness.bottom}, color, 0.0f);
        backend.DrawRoundedRect({bounds.x, bounds.y + thickness.top, thickness.left, bounds.height - thickness.top - thickness.bottom}, color, 0.0f);
        backend.DrawRoundedRect({bounds.x + bounds.width - thickness.right, bounds.y + thickness.top, thickness.right, bounds.height - thickness.top - thickness.bottom}, color, 0.0f);
    }

    void RenderWireframeMargin(const Element& element, IRenderBackend& backend, const Rect& bounds, float opacity, const attr::Wireframe& wireframe) {
        const attr::Thickness margin = element.Margin();
        RenderWireframeInsets(backend, {bounds.x - margin.left, bounds.y - margin.top, bounds.width + margin.left + margin.right, bounds.height + margin.top + margin.bottom}, margin, wireframe.marginColor, opacity);
    }

    void RenderWireframePadding(const Element& element, IRenderBackend& backend, const Rect& bounds, float opacity, const attr::Wireframe& wireframe) {
        RenderWireframeInsets(backend, bounds, element.Padding(), wireframe.paddingColor, opacity);
    }

    struct InspectionWireframe final {
        const Element& element;
        Rect bounds;
        float opacity;
    };

    void RenderInspectionWireframes(
        const std::vector<InspectionWireframe>& wireframes,
        IRenderBackend& backend) {
        // Инспекционные рамки рисуются после основного дерева без clip-областей.
        // Иначе собственный clip элемента и отрисовка соседей могут обрезать
        // стороны рамки или перекрыть её содержимым.
        for (const InspectionWireframe& wireframe : wireframes) {
            const Element& element = wireframe.element;
            if (element.HasInspectionWireframe()) {
                RenderWireframeMargin(
                    element,
                    backend,
                    wireframe.bounds,
                    wireframe.opacity,
                    element.InspectionWireframe());
                RenderWireframe(
                    backend,
                    wireframe.bounds,
                    wireframe.opacity,
                    element.CornerRadius(),
                    element.InspectionWireframe());
                RenderWireframePadding(
                    element,
                    backend,
                    wireframe.bounds,
                    wireframe.opacity,
                    element.InspectionWireframe());
            }
            if (element.HasSelectedWireframe()) {
                RenderWireframeMargin(
                    element,
                    backend,
                    wireframe.bounds,
                    wireframe.opacity,
                    element.SelectedWireframe());
                RenderWireframe(
                    backend,
                    wireframe.bounds,
                    wireframe.opacity,
                    element.CornerRadius(),
                    element.SelectedWireframe());
                RenderWireframePadding(
                    element,
                    backend,
                    wireframe.bounds,
                    wireframe.opacity,
                    element.SelectedWireframe());
            }
        }
    }

    void RenderDefaultElement(
        const Element& element,
        IRenderBackend& backend,
        Rect bounds,
        float opacity) {
        RenderChrome(element, backend, bounds, opacity);
        if (element.Type() == ElementType::textBlock) {
            RenderTextBlock(element, backend, bounds, opacity);
        } else if (element.Type() == ElementType::button
            || element.Type() == ElementType::iconButton) {
            const attr::Color foreground = element.Type() == ElementType::button
                ? ButtonColor(element, element.Foreground(), element.ActiveForeground())
                : element.Foreground();
            backend.DrawText(
                bounds,
                element.Text(),
                WithOpacity(foreground, opacity),
                element.FontSize(),
                element.FontWeight(),
                element.Type() == ElementType::button
                    ? element.ContentAlignmentValue()
                    : element.HorizontalAlignmentValue());
        } else if (element.Type() == ElementType::toggleSwitch) {
            RenderToggleSwitch(element, backend, bounds, opacity);
        } else if (element.Type() == ElementType::image) {
            backend.DrawImage(bounds, element.Source(), WithOpacity(element.Tint(), opacity));
        } else if (element.Type() == ElementType::svgImage) {
            backend.DrawImage(bounds, element.Source(), WithOpacity(element.Tint(), opacity));
        }
    }

    void RenderElement(
        const Element& element,
        IRenderBackend& backend,
        const RendererRegistry* renderers,
        float inheritedOffsetX,
        float inheritedOffsetY,
        float inheritedOpacity,
        std::vector<InspectionWireframe>& inspectionWireframes) {
        if (!element.IsPresent()) {
            return;
        }

        const VisualTransform defaults{};
        const auto& transform = element.States().Contains<VisualTransform>()
            ? element.State<VisualTransform>() : defaults;
        const float offsetX = inheritedOffsetX + element.RenderOffsetX() + transform.offsetX;
        const float offsetY = inheritedOffsetY + element.RenderOffsetY() + transform.offsetY;
        // Ограничиваем каждый множитель до композиции: opacity > 1 не усиливает альфу цвета или родителя.
        const float opacity = inheritedOpacity * std::clamp(element.Opacity(), 0.0f, 1.0f)
            * std::clamp(transform.opacity, 0.0f, 1.0f);
        const Rect bounds = Translate(element.Bounds(), offsetX, offsetY);
        const float childrenOffsetX = element.Type() == ElementType::scrollViewer
            ? offsetX - element.HorizontalOffset() : offsetX;
        const float childrenOffsetY = element.Type() == ElementType::scrollViewer
            ? offsetY - element.VerticalOffset() : offsetY;
        RenderWireframeMargin(element, backend, bounds, opacity, element.Wireframe());
        if (element.HasInspectionWireframe() || element.HasSelectedWireframe()) {
            inspectionWireframes.push_back({element, bounds, opacity});
        }
        backend.BeginClip(Translate(element.ClipBounds(), offsetX, offsetY));
        RenderInvocation context(backend, bounds, opacity,
            [&element, &backend, bounds, opacity]() {
                RenderDefaultElement(element, backend, bounds, opacity);
            },
            [&element, &backend, renderers, childrenOffsetX, childrenOffsetY, opacity, &inspectionWireframes]() {
                for (const auto& child : element.Children()) {
                    RenderElement(
                        *child,
                        backend,
                        renderers,
                        childrenOffsetX,
                        childrenOffsetY,
                        opacity,
                        inspectionWireframes);
                }
            });
        try {
            if (renderers == nullptr || !renderers->Render(element, context)) {
                context.RenderDefault();
            }
        } catch (...) {
            backend.EndClip();
            throw;
        }
        if (element.Type() == ElementType::scrollViewer) {
            RenderScrollBars(element, backend, bounds, opacity);
        }
        RenderWireframe(backend, bounds, opacity, element.CornerRadius(), element.Wireframe());
        RenderWireframePadding(element, backend, bounds, opacity, element.Wireframe());
        backend.EndClip();
    }
}

namespace universaldevkit::xamlruntime {
    RenderInvocation::RenderInvocation(
        IRenderBackend& backend,
        const Rect& bounds,
        float opacity,
        std::function<void()> defaultElementRenderer,
        std::function<void()> childrenRenderer)
        : backend(backend)
        , bounds(bounds)
        , opacity(opacity)
        , defaultElementRenderer(std::move(defaultElementRenderer))
        , childrenRenderer(std::move(childrenRenderer)) {
    }

    IRenderBackend& RenderInvocation::Backend() {
        return this->backend;
    }

    const Rect& RenderInvocation::Bounds() const {
        return this->bounds;
    }

    float RenderInvocation::Opacity() const {
        return this->opacity;
    }

    void RenderInvocation::RenderDefaultElement() {
        if (this->defaultElementRendered) {
            return;
        }

        this->defaultElementRendered = true;
        this->defaultElementRenderer();
        this->RenderChildren();
    }

    void RenderInvocation::RenderDefault() {
        this->RenderDefaultElement();
    }

    void RenderInvocation::RenderChildren() {
        if (!this->childrenRendered && this->childrenRenderer) {
            this->childrenRendered = true;
            this->childrenRenderer();
        }
    }

    RendererRegistry::RendererRegistry(StateRegistry states)
        : states(std::move(states)) {
    }

    //
    // API
    //
    void RendererRegistry::Prepare(Element& root) const {
        const auto found = this->renderers.find(root.Renderer());
        if (found != this->renderers.end()) {
            root.States().Prepare(this->states, found->second.stateType);
        }
        for (const auto& child : root.Children()) {
            this->Prepare(*child);
        }
    }

    bool RendererRegistry::Render(const Element& element, RenderInvocation& context) const {
        const auto found = this->renderers.find(element.Renderer());
        return !element.Renderer().empty() && found != this->renderers.end()
            && found->second.render(element, context);
    }

    void Render(Element& root, IRenderBackend& backend) {
        if (root.layoutInvalid) {
            layout(root, root.availableSize);
        }
        std::vector<details::InspectionWireframe> inspectionWireframes;
        details::RenderElement(root, backend, nullptr, 0.0f, 0.0f, 1.0f, inspectionWireframes);
        details::RenderInspectionWireframes(inspectionWireframes, backend);
    }

    void Render(Element& root, IRenderBackend& backend, const RendererRegistry& renderers) {
        renderers.Prepare(root);
        if (root.layoutInvalid) {
            layout(root, root.availableSize);
        }
        std::vector<details::InspectionWireframe> inspectionWireframes;
        details::RenderElement(root, backend, &renderers, 0.0f, 0.0f, 1.0f, inspectionWireframes);
        details::RenderInspectionWireframes(inspectionWireframes, backend);
    }
}