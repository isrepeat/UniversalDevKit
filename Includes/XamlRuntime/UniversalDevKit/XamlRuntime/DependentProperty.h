#pragma once

#include <functional>
#include <utility>

namespace xaml {
    template <typename TValue>
    class DependentProperty final {
    public:
        using ChangedHandler = std::function<void(const TValue&)>;

        DependentProperty() = default;
        ~DependentProperty() = default;

        const TValue& Value() const {
            return this->value;
        }

        void Set(TValue value) {
            if (this->value == value) {
                return;
            }
            this->value = std::move(value);
            if (this->changedHandler) {
                this->changedHandler(this->value);
            }
        }

        void SetChangedHandler(ChangedHandler value) {
            this->changedHandler = std::move(value);
        }

    private:
        TValue value{};
        ChangedHandler changedHandler;
    };
}