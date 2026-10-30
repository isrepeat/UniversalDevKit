#pragma once

#include "ScrollController.h"

#include <functional>

namespace xaml {
    class AnimationController;
    class Element;

    enum class GestureKind {
        none,
        tap,
        pan,
        scroll,
    };

    enum class GestureDirection {
        none,
        left,
        right,
    };

    struct GestureContext {
        Element& root;
        Element& target;
        Element* scrollViewer;
        AnimationController& animations;
        float downX;
        float downY;
        float previousX;
        float previousY;
        float currentX;
        float currentY;
    };

    struct GestureResult {
        GestureKind kind = GestureKind::none;
        GestureDirection direction = GestureDirection::none;
        Element* target = nullptr;
        int itemIndex = -1;
    };

    class GestureRecognizer {
    public:
        virtual ~GestureRecognizer() = default;

        virtual bool Update(const GestureContext& context) = 0;
        virtual GestureResult Complete(const GestureContext& context) = 0;
        virtual void Cancel() = 0;
        virtual bool UpdateInertia() = 0;
    };

    class TapGestureRecognizer final : public GestureRecognizer {
    public:
        bool Update(const GestureContext& context) override;
        GestureResult Complete(const GestureContext& context) override;
        void Cancel() override;
        bool UpdateInertia() override;
    };

    class PanGestureRecognizer final : public GestureRecognizer {
    public:
        using TargetPredicate = std::function<bool(const Element&)>;

        void SetTargetPredicate(TargetPredicate value);

        //
        // GestureRecognizer
        //
        bool Update(const GestureContext& context) override;
        GestureResult Complete(const GestureContext& context) override;
        void Cancel() override;
        bool UpdateInertia() override;

    private:
        TargetPredicate targetPredicate;
    };

    class ScrollGestureRecognizer final : public GestureRecognizer {
    public:
        bool Update(const GestureContext& context) override;
        GestureResult Complete(const GestureContext& context) override;
        void Cancel() override;
        bool UpdateInertia() override;

    private:
        bool isDragging = false;
        ScrollController scrollController;
    };
}