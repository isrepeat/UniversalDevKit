#pragma once

#include "GestureRecognizer.h"

#include <functional>
#include <memory>
#include <vector>

namespace xaml {
    class AnimationController;
    class Element;

    class InteractionController final {
    public:
        InteractionController() = default;
        ~InteractionController() = default;

        using PanTargetPredicate = std::function<bool(const Element&)>;

        void PointerDown(Element& root, AnimationController& animations, float x, float y);
        bool PointerMove(float x, float y);
        GestureResult PointerUp(Element& root, AnimationController& animations, float x, float y);
        bool ScrollWheel(Element& root, float x, float y, float horizontalDelta, float verticalDelta);
        void Cancel();
        bool Update();
        bool HasCapture() const;
        void SetPanTargetPredicate(PanTargetPredicate value);

    private:
        void EnsureRecognizers();
        GestureContext CreateContext(Element& root, AnimationController& animations, float x, float y) const;
        int FindListItemIndex(Element& element) const;

    private:
        Element* capturedElement = nullptr;
        Element* scrollViewer = nullptr;
        Element* inputRoot = nullptr;
        AnimationController* animationController = nullptr;
        float touchDownX = 0.0f;
        float touchDownY = 0.0f;
        float lastTouchX = 0.0f;
        float lastTouchY = 0.0f;
        std::vector<std::unique_ptr<GestureRecognizer>> recognizers;
        GestureRecognizer* activeRecognizer = nullptr;
        PanGestureRecognizer* panRecognizer = nullptr;
    };
}