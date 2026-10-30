#pragma once
#include <functional>
#include <initializer_list>
#include <iterator>
#include <list>
#include <cstddef>
#include <utility>
#include <vector>

namespace xaml {
    enum class CollectionChangeKind { insert, remove, replace, move, reset };

    struct CollectionChange {
        CollectionChangeKind kind = CollectionChangeKind::reset;
        size_t index = 0;
        size_t oldIndex = 0;
        size_t count = 0;
    };

    template <typename TValue>
    class ObservableCollection final {
    public:
        using value_type = TValue;
        using iterator = typename std::list<TValue>::iterator;
        using const_iterator = typename std::list<TValue>::const_iterator;
        using ChangedHandler = std::function<void(CollectionChange)>;
        using Unsubscribe = std::function<void()>;

        ObservableCollection() = default;
        ObservableCollection(std::initializer_list<TValue> value)
            : values(value) {
        }
        ~ObservableCollection() = default;

        ObservableCollection(const ObservableCollection&) = delete;
        ObservableCollection& operator=(const ObservableCollection&) = delete;

        iterator begin() { return this->values.begin(); }
        iterator end() { return this->values.end(); }
        const_iterator begin() const { return this->values.begin(); }
        const_iterator end() const { return this->values.end(); }
        size_t size() const { return this->values.size(); }

        template <typename... TArguments>
        TValue& EmplaceBack(TArguments&&... arguments) {
            this->values.emplace_back(std::forward<TArguments>(arguments)...);
            TValue& value = this->values.back();
            this->Notify({CollectionChangeKind::insert, this->values.size() - 1, 0, 1});
            return value;
        }

        iterator Erase(iterator value) {
            const size_t index = static_cast<size_t>(std::distance(this->values.begin(), value));
            const iterator result = this->values.erase(value);
            this->Notify({CollectionChangeKind::remove, index, 0, 1});
            return result;
        }

        void Clear() {
            if (this->values.empty()) {
                return;
            }
            this->values.clear();
            this->Notify({CollectionChangeKind::reset});
        }

        Unsubscribe Subscribe(ChangedHandler handler) const {
            this->handlers.push_back(std::move(handler));
            const size_t index = this->handlers.size() - 1;
            return [this, index]() { this->handlers[index] = nullptr; };
        }

    private:
        void Notify(CollectionChange change) const {
            for (const ChangedHandler& handler : this->handlers) {
                if (handler) {
                    handler(change);
                }
            }
        }

    private:
        std::list<TValue> values;
        mutable std::vector<ChangedHandler> handlers;
    };
}