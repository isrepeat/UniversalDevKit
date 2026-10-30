#include "../../Includes/XamlRuntime/UniversalDevKit/XamlRuntime/GestureRecognizer.h"

#include "../../Includes/XamlRuntime/UniversalDevKit/XamlRuntime/ScrollController.h"
#include "../../Includes/XamlRuntime/UniversalDevKit/XamlRuntime/XamlLayout.h"
#include "../../Includes/XamlRuntime/UniversalDevKit/XamlRuntime/Animation.h"
#include "../../Includes/XamlRuntime/UniversalDevKit/XamlRuntime/Input.h"

#include <utility>
#include <chrono>
#include <cmath>

namespace xaml {
    namespace _details {
        constexpr float GestureThreshold = 8.0f;
        constexpr float PanCompletionThreshold = 180.0f;
    }

    bool TapGestureRecognizer::Update(const GestureContext& context) {
        static_cast<void>(context);
        return false;
    }

    GestureResult TapGestureRecognizer::Complete(const GestureContext& context) {
        if (HitTest(context.root, context.currentX, context.currentY) != &context.target
            || !HandleTap(context.target)) {
            return {};
        }
        context.animations.Start(context.target, AnimationTrigger::pointerUp);
        if (context.target.Type() == ElementType::toggleSwitch) {
            context.animations.Start(context.target, AnimationTrigger::toggled);
        }
        return {GestureKind::tap, GestureDirection::none, &context.target};
    }

    void TapGestureRecognizer::Cancel() {
    }

    bool TapGestureRecognizer::UpdateInertia() {
        return false;
    }

    void PanGestureRecognizer::SetTargetPredicate(TargetPredicate value) {
        this->targetPredicate = std::move(value);
    }

    bool PanGestureRecognizer::Update(const GestureContext& context) {
        const float horizontalDistance = context.currentX - context.downX;
        const float verticalDistance = context.currentY - context.downY;
        if (std::max(std::abs(horizontalDistance), std::abs(verticalDistance)) < _details::GestureThreshold
            || std::abs(horizontalDistance) <= std::abs(verticalDistance)
            || !this->targetPredicate
            || !this->targetPredicate(context.target)) {
            return false;
        }
        context.target.SetRenderOffsetX(horizontalDistance);
        return true;
    }

    GestureResult PanGestureRecognizer::Complete(const GestureContext& context) {
        const float horizontalDistance = context.currentX - context.downX;
        if (std::abs(horizontalDistance) < _details::PanCompletionThreshold) {
            context.animations.Animate(
                context.target,
                AnimatedProperty::renderOffsetX,
                context.target.RenderOffsetX(),
                0.0f,
                std::chrono::milliseconds(180));
            return {};
        }
        const GestureDirection direction = horizontalDistance < 0.0f
            ? GestureDirection::left : GestureDirection::right;
        const Rect rootBounds = context.root.Bounds();
        const Rect targetBounds = context.target.Bounds();
        const float targetOffset = direction == GestureDirection::left
            ? -targetBounds.x - targetBounds.width
            : rootBounds.width - targetBounds.x;
        context.animations.Animate(
            context.target,
            AnimatedProperty::renderOffsetX,
            context.target.RenderOffsetX(),
            targetOffset,
            std::chrono::milliseconds(220));
        return {GestureKind::pan, direction, &context.target};
    }

    void PanGestureRecognizer::Cancel() {
    }

    bool PanGestureRecognizer::UpdateInertia() {
        return false;
    }

    bool ScrollGestureRecognizer::Update(const GestureContext& context) {
        const float horizontalDistance = context.currentX - context.downX;
        const float verticalDistance = context.currentY - context.downY;
        if (context.scrollViewer == nullptr
            || std::max(std::abs(horizontalDistance), std::abs(verticalDistance)) < _details::GestureThreshold
            || std::abs(verticalDistance) <= std::abs(horizontalDistance)) {
            return false;
        }
        if (!this->isDragging) {
            this->scrollController.Begin(*context.scrollViewer);
            this->isDragging = true;
        }
        return this->scrollController.Drag(context.previousY - context.currentY);
    }

    GestureResult ScrollGestureRecognizer::Complete(const GestureContext& context) {
        if (!this->isDragging) {
            return {};
        }
        this->scrollController.End();
        this->isDragging = false;
        return {GestureKind::scroll, GestureDirection::none, &context.target};
    }

    void ScrollGestureRecognizer::Cancel() {
        this->scrollController.Cancel();
        this->isDragging = false;
    }

    bool ScrollGestureRecognizer::UpdateInertia() {
        return this->scrollController.Update();
    }
}