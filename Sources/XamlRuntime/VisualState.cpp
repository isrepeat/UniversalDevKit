#include "../../Includes/XamlRuntime/UniversalDevKit/XamlRuntime/VisualState.h"

#include <charconv>
#include <sstream>
#include <locale>
#include <cmath>

namespace universaldevkit::xamlruntime {
    namespace details {
        float ParseStateFloat(const std::string& value) {
            std::istringstream input(value);
            input.imbue(std::locale::classic());
            input >> std::noskipws;
            float result = 0.0f;
            if (!(input >> result) || input.peek() != std::char_traits<char>::eof() || !std::isfinite(result)) {
                throw std::invalid_argument("Expected a finite float: " + value);
            }
            return result;
        }

        int ParseStateInt(const std::string& value) {
            int result = 0;
            const auto parsed = std::from_chars(value.data(), value.data() + value.size(), result);
            if (parsed.ec != std::errc{} || parsed.ptr != value.data() + value.size()) {
                throw std::invalid_argument("Expected an integer: " + value);
            }
            return result;
        }

        bool ParseStateBool(const std::string& value) {
            if (value == "true") {
                return true;
            }
            if (value == "false") {
                return false;
            }
            throw std::invalid_argument("Expected true or false: " + value);
        }
    } // namespace details

    StateRegistry::StateRegistry() {
        this->Register<VisualTransform>();
        this->Register<EmptyState>();
    }

    //
    // API
    //
    void StateRegistry::Require(std::type_index type) const {
        if (this->factories.find(type) == this->factories.end()) {
            throw std::invalid_argument("Unregistered visual state type");
        }
    }

    std::shared_ptr<void> StateRegistry::Create(std::type_index type) const {
        this->Require(type);
        return this->factories.at(type)();
    }

    //
    // API
    //
    void ElementStates::Prepare(const StateRegistry& registry, std::type_index type) {
        registry.Require(type);
        if (this->values.find(type) == this->values.end()) {
            this->values.emplace(type, registry.Create(type));
        }
    }

    //
    // Internal
    //
    void ElementStates::Clear() {
        this->values.clear();
    }
}