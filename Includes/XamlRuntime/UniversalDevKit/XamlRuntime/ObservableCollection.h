#pragma once
#include <UniversalDevKit/Helpers/Event/Signal.h>

#include "Config.h"
#include "Export.h"

#include <initializer_list>
#include <functional>
#include <iterator>
#include <cstddef>
#include <utility>
#include <vector>
#include <list>

namespace universaldevkit::xamlruntime {
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
            auto connection = this->changed.Subscribe(std::move(handler));
            return [connection = std::move(connection)]() { connection->Disconnect(); };
        }

    private:
        void Notify(CollectionChange change) const {
            this->changed.Invoke(change);
        }

    private:
        std::list<TValue> values;
        mutable universaldevkit::helpers::event::Signal<void(CollectionChange)> changed;
    };
}