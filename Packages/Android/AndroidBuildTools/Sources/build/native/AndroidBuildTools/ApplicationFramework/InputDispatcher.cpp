#include "InputDispatcher.h"

namespace application_framework {
    //
    // API
    //
    void InputDispatcher::PointerDown(xaml::Element& root, xaml::AnimationController& animations, float x, float y) {
        this->interaction.PointerDown(root, animations, x, y);
    }

    void InputDispatcher::PointerMove(float x, float y) {
        this->interaction.PointerMove(x, y);
    }

    void InputDispatcher::PointerUp(xaml::Element& root, xaml::AnimationController& animations, float x, float y) {
        this->interaction.PointerUp(root, animations, x, y);
    }

    void InputDispatcher::Cancel() {
        this->interaction.Cancel();
    }

    bool InputDispatcher::Update() {
        return this->interaction.Update();
    }
}