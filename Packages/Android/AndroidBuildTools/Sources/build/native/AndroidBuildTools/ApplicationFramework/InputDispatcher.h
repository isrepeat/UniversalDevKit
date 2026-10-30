#pragma once
#include <UniversalDevKit/XamlRuntime/InteractionController.h>
#include <UniversalDevKit/XamlRuntime/Animation.h>

namespace application_framework {
    class InputDispatcher final {
    public:
        void PointerDown(xaml::Element& root, xaml::AnimationController& animations, float x, float y);
        void PointerMove(float x, float y);
        void PointerUp(xaml::Element& root, xaml::AnimationController& animations, float x, float y);
        void Cancel();
        bool Update();

    private:
        xaml::InteractionController interaction;
    };
}