#include "../../Includes/XamlRuntime/UniversalDevKit/XamlRuntime/ScrollController.h"

#include "../../Includes/XamlRuntime/UniversalDevKit/XamlRuntime/XamlLayout.h"

#include <algorithm>
#include <cmath>

namespace universaldevkit::xamlruntime {
    namespace details {
        constexpr float velocityThreshold = 35.0f;
        constexpr float maximumVelocity = 8000.0f;
        constexpr float stopVelocity = 5.0f;
        constexpr float deceleration = 4.0f;
        constexpr float maximumFrameDuration = 1.0f / 30.0f;
    } // namespace details

    void ScrollController::Begin(Element& scrollViewer) {
        this->target = &scrollViewer;
        this->samples.clear();
        this->dragDistance = 0.0f;
        this->velocity = 0.0f;
        this->isInertial = false;
        this->updatedAt = std::chrono::steady_clock::now();
        this->samples.push_back({this->updatedAt, this->dragDistance});
    }

    bool ScrollController::Drag(float verticalDelta) {
        if (this->target == nullptr) {
            return false;
        }
        const float offset = this->target->VerticalOffset();
        this->target->SetVerticalOffset(offset + verticalDelta);
        if (this->target->VerticalOffset() == offset) {
            return false;
        }
        const auto now = std::chrono::steady_clock::now();
        this->dragDistance += verticalDelta;
        this->samples.push_back({now, this->dragDistance});
        const auto oldest = now - std::chrono::milliseconds(100);
        this->samples.erase(std::remove_if(this->samples.begin(), this->samples.end(),
            [oldest](const Sample& sample) { return sample.time < oldest; }), this->samples.end());
        return true;
    }

    void ScrollController::End() {
        if (this->samples.size() < 2) {
            this->Cancel();
            return;
        }
        const auto duration = this->samples.back().time - this->samples.front().time;
        const float seconds = std::chrono::duration<float>(duration).count();
        if (seconds <= 0.0f) {
            this->Cancel();
            return;
        }
        const float distance = this->samples.back().position - this->samples.front().position;
        this->velocity = std::clamp(
            distance / seconds,
            -details::maximumVelocity,
            details::maximumVelocity);
        this->isInertial = std::abs(this->velocity) >= details::velocityThreshold;
        this->updatedAt = std::chrono::steady_clock::now();
        this->samples.clear();
        this->dragDistance = 0.0f;
    }

    bool ScrollController::Update() {
        if (!this->isInertial || this->target == nullptr) {
            return false;
        }
        const auto now = std::chrono::steady_clock::now();
        const float elapsed = std::min(
            details::maximumFrameDuration,
            std::chrono::duration<float>(now - this->updatedAt).count());
        this->updatedAt = now;
        if (elapsed <= 0.0f) {
            return true;
        }
        const float offset = this->target->VerticalOffset();
        const auto motionStep = universaldevkit::helpers::math::Motion::ExponentialStep(this->velocity, details::deceleration, elapsed);
        const float distance = motionStep.distance;
        this->target->SetVerticalOffset(offset + distance);
        if (this->target->VerticalOffset() == offset) {
            this->Cancel();
            return false;
        }
        this->velocity = motionStep.velocity;
        if (std::abs(this->velocity) < details::stopVelocity) {
            this->Cancel();
        }
        return true;
    }

    void ScrollController::Cancel() {
        this->samples.clear();
        this->velocity = 0.0f;
        this->isInertial = false;
    }
}