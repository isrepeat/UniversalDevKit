#include "../../Includes/XamlRuntime/UniversalDevKit/XamlRuntime/InteractionController.h"

#include "../../Includes/XamlRuntime/UniversalDevKit/XamlRuntime/XamlLayout.h"
#include "../../Includes/XamlRuntime/UniversalDevKit/XamlRuntime/Animation.h"
#include "../../Includes/XamlRuntime/UniversalDevKit/XamlRuntime/Input.h"

#include <algorithm>

namespace universaldevkit::xamlruntime {
    void InteractionController::PointerDown(
        Element& root,
        AnimationController& animations,
        float x,
        float y) {
        this->EnsureRecognizers();
        this->inputRoot = &root;
        Element* const visualElement = HitTestVisual(root, x, y);
        this->capturedElement = HitTest(root, x, y);
        if (this->capturedElement == nullptr) {
            this->capturedElement = visualElement;
        }
        this->scrollViewer = visualElement;
        this->animationController = &animations;
        while (this->scrollViewer != nullptr && this->scrollViewer->Type() != ElementType::scrollViewer) {
            this->scrollViewer = this->scrollViewer->Parent();
        }
        this->touchDownX = x;
        this->touchDownY = y;
        this->lastTouchX = x;
        this->lastTouchY = y;
        this->activeRecognizer = nullptr;
        for (const std::unique_ptr<GestureRecognizer>& recognizer : this->recognizers) {
            recognizer->Cancel();
        }
        if (this->capturedElement != nullptr) {
            animations.Start(*this->capturedElement, AnimationTrigger::pointerDown);
        }
    }

    bool InteractionController::PointerMove(float x, float y) {
        if (this->capturedElement == nullptr) {
            return false;
        }
        if (this->animationController == nullptr) {
            return false;
        }
        GestureContext context = this->CreateContext(*this->inputRoot, *this->animationController, x, y);
        if (this->activeRecognizer == nullptr) {
            for (const std::unique_ptr<GestureRecognizer>& recognizer : this->recognizers) {
                if (recognizer->Update(context)) {
                    this->activeRecognizer = recognizer.get();
                    break;
                }
            }
        } else if (!this->activeRecognizer->Update(context)) {
            return false;
        }
        this->lastTouchX = x;
        this->lastTouchY = y;
        return this->activeRecognizer != nullptr;
    }

    GestureResult InteractionController::PointerUp(
        Element& root,
        AnimationController& animations,
        float x,
        float y) {
        Element* const element = this->capturedElement;
        if (element == nullptr) {
            return {};
        }
        GestureContext context = this->CreateContext(root, animations, x, y);
        this->capturedElement = nullptr;
        this->scrollViewer = nullptr;
        this->inputRoot = nullptr;
        this->animationController = nullptr;
        GestureResult result;
        if (this->activeRecognizer != nullptr) {
            result = this->activeRecognizer->Complete(context);
        } else {
            result = this->recognizers.front()->Complete(context);
        }
        this->activeRecognizer = nullptr;
        this->lastTouchX = x;
        this->lastTouchY = y;
        if (result.target != nullptr) {
            result.itemIndex = this->FindListItemIndex(*result.target);
        }
        return result;
    }

    bool InteractionController::ScrollWheel(
        Element& root,
        float x,
        float y,
        float horizontalDelta,
        float verticalDelta) {
        Element* element = HitTestVisual(root, x, y);
        while (element != nullptr && element->Type() != ElementType::scrollViewer) {
            element = element->Parent();
        }
        if (element == nullptr) {
            return false;
        }
        const float horizontalOffset = std::clamp(element->HorizontalOffset() + horizontalDelta, 0.0f,
            std::max(0.0f, element->Extent().width - element->Viewport().width));
        const float verticalOffset = std::clamp(element->VerticalOffset() + verticalDelta, 0.0f,
            std::max(0.0f, element->Extent().height - element->Viewport().height));
        if (horizontalOffset == element->HorizontalOffset() && verticalOffset == element->VerticalOffset()) {
            return false;
        }
        element->SetHorizontalOffset(horizontalOffset);
        element->SetVerticalOffset(verticalOffset);
        return true;
    }

    void InteractionController::Cancel() {
        this->capturedElement = nullptr;
        this->scrollViewer = nullptr;
        this->inputRoot = nullptr;
        this->animationController = nullptr;
        this->activeRecognizer = nullptr;
        for (const std::unique_ptr<GestureRecognizer>& recognizer : this->recognizers) {
            recognizer->Cancel();
        }
    }

    bool InteractionController::Update() {
        bool changed = false;
        for (const std::unique_ptr<GestureRecognizer>& recognizer : this->recognizers) {
            changed = recognizer->UpdateInertia() || changed;
        }
        return changed;
    }

    bool InteractionController::HasCapture() const {
        return this->capturedElement != nullptr;
    }

    void InteractionController::SetPanTargetPredicate(PanTargetPredicate value) {
        this->EnsureRecognizers();
        this->panRecognizer->SetTargetPredicate(std::move(value));
    }

    void InteractionController::EnsureRecognizers() {
        if (!this->recognizers.empty()) {
            return;
        }
        this->recognizers.push_back(std::make_unique<TapGestureRecognizer>());
        this->recognizers.push_back(std::make_unique<ScrollGestureRecognizer>());
        auto pan = std::make_unique<PanGestureRecognizer>();
        this->panRecognizer = pan.get();
        this->recognizers.push_back(std::move(pan));
    }

    GestureContext InteractionController::CreateContext(
        Element& root,
        AnimationController& animations,
        float x,
        float y) const {
        return {root, *this->capturedElement, this->scrollViewer, animations,
            this->touchDownX, this->touchDownY, this->lastTouchX, this->lastTouchY, x, y};
    }

    int InteractionController::FindListItemIndex(Element& element) const {
        Element* item = &element;
        while (item->Parent() != nullptr) {
            Element* const parent = item->Parent();
            if (parent->Type() == ElementType::listView) {
                const auto& children = parent->Children();
                for (size_t index = 0; index < children.size(); ++index) {
                    if (children[index].get() == item) {
                        return static_cast<int>(index);
                    }
                }
            }
            item = parent;
        }
        return -1;
    }
}