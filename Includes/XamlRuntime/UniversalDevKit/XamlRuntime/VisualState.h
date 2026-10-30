#pragma once

#include "Storyboard.h"

#include <initializer_list>
#include <unordered_map>
#include <type_traits>
#include <functional>
#include <stdexcept>
#include <typeindex>
#include <utility>
#include <memory>
#include <string>
#include <vector>

namespace xaml {
    // Общие каналы композиции, не зависящие от конкретного эффекта.
    struct VisualTransform {
        float opacity = 1.0f;
        float offsetX = 0.0f;
        float offsetY = 0.0f;
    };

    struct EmptyState {};

    namespace _details {
        float ParseStateFloat(const std::string& value);
        int ParseStateInt(const std::string& value);
        bool ParseStateBool(const std::string& value);

        template<typename TValue>
        TValue ParseStateValue(const std::string& value) {
            static_assert(std::is_same_v<TValue, float> || std::is_same_v<TValue, int>
                || std::is_same_v<TValue, bool> || std::is_same_v<TValue, std::string>,
                "Unsupported XAML option type");
            if constexpr (std::is_same_v<TValue, float>) {
                return ParseStateFloat(value);
            } else if constexpr (std::is_same_v<TValue, int>) {
                return ParseStateInt(value);
            } else if constexpr (std::is_same_v<TValue, bool>) {
                return ParseStateBool(value);
            } else {
                return value;
            }
        }
    }

    template<typename TOwner, typename TValue>
    struct OptionDeclaration {
        std::string name;
        TValue TOwner::* member;
        bool (*validate)(const TValue&) = nullptr;
    };

    template<typename TOwner, typename TValue>
    OptionDeclaration<TOwner, TValue> Option(
        std::string name, TValue TOwner::* member,
        bool (*validate)(const TValue&) = nullptr) {
        if (name.empty() || member == nullptr) {
            throw std::invalid_argument("Invalid animation option declaration");
        }
        return {std::move(name), member, validate};
    }

    template<typename TOwner>
    class OptionBinding final {
    public:
        template<typename TValue>
        OptionBinding(OptionDeclaration<TOwner, TValue> declaration)
            : name(std::move(declaration.name))
            , apply([member = declaration.member, validate = declaration.validate](
                TOwner& target, const std::string* text, const TOwner& defaults) {
                const TValue value = text ? _details::ParseStateValue<TValue>(*text) : defaults.*member;
                if (validate && !validate(value)) {
                    throw std::invalid_argument("Animation option is outside its allowed range");
                }
                target.*member = value;
            }) {
        }

        const std::string& Name() const {
            return this->name;
        }

        void Apply(TOwner& target, const std::string* value, const TOwner& defaults) const {
            try {
                this->apply(target, value, defaults);
            } catch (const std::exception& error) {
                throw std::invalid_argument("Animation option '" + this->name + "': " + error.what());
            }
        }

    private:
        std::string name;
        std::function<void(TOwner&, const std::string*, const TOwner&)> apply;
    };

    template<typename TState>
    class OptionSchema final {
    public:
        explicit OptionSchema(std::initializer_list<OptionBinding<TState>> options)
            : options(options) {
            for (size_t index = 0; index < this->options.size(); ++index) {
                for (size_t previous = 0; previous < index; ++previous) {
                    if (this->options[index].Name() == this->options[previous].Name()) {
                        throw std::invalid_argument("Duplicate animation option: " + this->options[index].Name());
                    }
                }
            }
        }

        TState Bind(const TState& current, const AnimationSettings& settings) const {
            for (const auto& attribute : settings.Values()) {
                bool known = false;
                for (const auto& option : this->options) {
                    if (option.Name() == attribute.first) {
                        known = true;
                        break;
                    }
                }
                if (!known) {
                    throw std::invalid_argument("Unknown animation option: " + attribute.first);
                }
            }
            TState result = current;
            const TState defaults{};
            for (const auto& option : this->options) {
                const auto found = settings.Values().find(option.Name());
                option.Apply(result, found == settings.Values().end() ? nullptr : &found->second, defaults);
            }
            return result;
        }

    private:
        std::vector<OptionBinding<TState>> options;
    };

    class StateRegistry final {
    public:
        StateRegistry();

        template<typename TState>
        void Register() {
            static_assert(std::is_default_constructible_v<TState>
                && std::is_copy_constructible_v<TState> && std::is_copy_assignable_v<TState>,
                "State must be default constructible and copyable");
            const auto result = this->factories.emplace(std::type_index(typeid(TState)),
                []() -> std::shared_ptr<void> { return std::make_shared<TState>(); });
            if (!result.second) {
                throw std::invalid_argument("State type already registered");
            }
        }

        void Require(std::type_index type) const;
        std::shared_ptr<void> Create(std::type_index type) const;

    private:
        std::unordered_map<std::type_index, std::function<std::shared_ptr<void>()>> factories;
    };

    // Принадлежит одному Element. Адреса подготовленных объектов сохраняются до вызова Clear().
    class ElementStates final {
    public:
        ElementStates() = default;
        ElementStates(const ElementStates&) = delete;
        ElementStates& operator=(const ElementStates&) = delete;
        void Prepare(const StateRegistry& registry, std::type_index type);

        template<typename TState>
        TState& Get() {
            const auto found = this->values.find(std::type_index(typeid(TState)));
            if (found == this->values.end()) {
                throw std::logic_error("Visual state is not prepared");
            }
            return *static_cast<TState*>(found->second.get());
        }

        template<typename TState>
        const TState& Get() const {
            const auto found = this->values.find(std::type_index(typeid(TState)));
            if (found == this->values.end()) {
                throw std::logic_error("Visual state is not prepared");
            }
            return *static_cast<const TState*>(found->second.get());
        }

        template<typename TState>
        bool Contains() const {
            return this->values.find(std::type_index(typeid(TState))) != this->values.end();
        }

    private:
        friend class AnimationController;
        void Clear();

    private:
        std::unordered_map<std::type_index, std::shared_ptr<void>> values;
    };
}