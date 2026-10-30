#pragma once

#include <chrono>
#include <vector>

namespace xaml {
    class Element;

    class ScrollController final {
    public:
        void Begin(Element& scrollViewer);
        bool Drag(float verticalDelta);
        void End();
        bool Update();
        void Cancel();

    private:
        struct Sample {
            std::chrono::steady_clock::time_point time;
            float position = 0.0f;
        };

    private:
        Element* target = nullptr;
        std::vector<Sample> samples;
        std::chrono::steady_clock::time_point updatedAt{};
        float dragDistance = 0.0f;
        float velocity = 0.0f;
        bool isInertial = false;
    };
}