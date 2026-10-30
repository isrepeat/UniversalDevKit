#pragma once

#include "XamlLayout.h"

#include <initializer_list>
#include <unordered_map>
#include <string_view>
#include <functional>

namespace xaml {
    struct ShaderUniform {
        std::string_view name;
        float values[4]{};
        int valueCount = 0;
    };

    class IRenderBackend {
    public:
        virtual ~IRenderBackend() = default;

        virtual void BeginClip(const Rect& bounds) = 0;
        virtual void EndClip() = 0;
        virtual void DrawOutline(const Rect& bounds, attr::Color color) = 0;
        virtual void DrawRoundedRect(
            const Rect& bounds,
            attr::Color color,
            float cornerRadius) = 0;
        virtual void DrawRoundedRectOutline(
            const Rect& bounds,
            attr::Color color,
            float cornerRadius,
            float thickness) = 0;
        virtual void DrawShader(
            std::string_view shaderName,
            const Rect& bounds,
            std::initializer_list<ShaderUniform> uniforms) = 0;
        virtual void DrawText(
            const Rect& bounds,
            std::string_view text,
            attr::Color color,
            float fontSize,
            std::string_view fontWeight,
            attr::Alignment horizontalAlignment) = 0;
        virtual void DrawImage(
            const Rect& bounds,
            std::string_view source,
            attr::Color tint) = 0;
    };

    class RenderInvocation {
    public:
        RenderInvocation(
            IRenderBackend& backend,
            const Rect& bounds,
            float opacity,
            std::function<void()> defaultElementRenderer,
            std::function<void()> childrenRenderer = {});
        IRenderBackend& Backend();
        const Rect& Bounds() const;
        float Opacity() const;
        void RenderDefaultElement();
        void RenderDefault();
        void RenderChildren();

    private:
        IRenderBackend& backend;
        const Rect& bounds;
        float opacity;
        std::function<void()> defaultElementRenderer;
        bool defaultElementRendered = false;
        std::function<void()> childrenRenderer;
        bool childrenRendered = false;
    };

    template<typename TState>
    class RenderContext final {
    public:
        RenderContext(RenderInvocation& render, const TState& state)
            : render(render)
            , state(state) {
        }

        const TState& State() const {
            return this->state;
        }

        IRenderBackend& Backend() {
            return this->render.Backend();
        }

        const Rect& Bounds() const {
            return this->render.Bounds();
        }

        float Opacity() const {
            return this->render.Opacity();
        }

        void RenderDefaultElement() {
            this->render.RenderDefaultElement();
        }

        void RenderDefault() {
            this->render.RenderDefault();
        }

        void RenderChildren() {
            this->render.RenderChildren();
        }

    private:
        RenderInvocation& render;
        const TState& state;
    };

    class RendererRegistry final {
    public:
        explicit RendererRegistry(StateRegistry states = {});

        template<typename TState>
        void Register(std::string name, bool (*renderer)(const Element&, RenderContext<TState>&)) {
            this->states.Require(std::type_index(typeid(TState)));
            if (name.empty() || renderer == nullptr) {
                throw std::invalid_argument("Renderer name and handler are required");
            }
            Entry entry{
                std::type_index(typeid(TState)),
                [renderer](const Element& element, RenderInvocation& invocation) {
                    RenderContext<TState> context(invocation, element.State<TState>());
                    return renderer(element, context);
                },
            };
            if (!this->renderers.emplace(std::move(name), std::move(entry)).second) {
                throw std::invalid_argument("Renderer name already registered");
            }
        }

        void Prepare(Element& root) const;
        bool Render(const Element& element, RenderInvocation& context) const;

    private:
        struct Entry {
            std::type_index stateType;
            std::function<bool(const Element&, RenderInvocation&)> render;
        };

    private:
        StateRegistry states;
        std::unordered_map<std::string, Entry> renderers;
    };

    void Render(Element& root, IRenderBackend& backend);
    void Render(Element& root, IRenderBackend& backend, const RendererRegistry& renderers);
}