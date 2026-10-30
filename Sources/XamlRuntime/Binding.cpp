#include "../../Includes/XamlRuntime/UniversalDevKit/XamlRuntime/Binding.h"

namespace xaml {
    BindingScope::~BindingScope() {
        this->Clear();
    }

    //
    // API
    //
    void BindingScope::Clear() {
        for (const std::function<void()>& unsubscribe : this->unsubscriptions) {
            unsubscribe();
        }
        this->unsubscriptions.clear();
        this->sourceUpdates.clear();
        this->runtimeTargets.clear();
    }

    void BindingScope::UpdateSource(Element& element) const {
        for (const SourceUpdate& sourceUpdate : this->sourceUpdates) {
            if (sourceUpdate.element == &element) {
                sourceUpdate.update();
            }
        }
    }

    void BindingScope::AddRuntimeSubscription(std::function<void()> unsubscribe) {
        if (unsubscribe) {
            this->unsubscriptions.push_back(std::move(unsubscribe));
        }
    }

    void BindingScope::AddRuntimeSourceUpdate(Element& element, std::function<void()> update) {
        this->sourceUpdates.push_back({&element, std::move(update)});
    }

    std::shared_ptr<Element*> BindingScope::AddRuntimeTarget(Element& element) {
        auto target = std::make_shared<Element*>(&element);
        this->runtimeTargets.push_back(target);
        return target;
    }

    void BindingScope::RetargetRuntimeElement(Element& previous, Element& replacement) {
        for (const auto& target : this->runtimeTargets) {
            if (*target == &previous) {
                *target = &replacement;
            }
        }
        for (auto& source : this->sourceUpdates) {
            if (source.element == &previous) {
                source.element = &replacement;
            }
        }
    }
}