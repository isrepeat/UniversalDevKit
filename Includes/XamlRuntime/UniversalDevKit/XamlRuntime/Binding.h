#pragma once
#include "XamlLayout.h"
#include "Config.h"
#include "Export.h"

#include <functional>
#include <utility>
#include <vector>

namespace universaldevkit::xamlruntime {
    class UNIVERSALDEVKIT_XAMLRUNTIME_API BindingScope final {
    public:
        BindingScope() = default;
        ~BindingScope();

        BindingScope(const BindingScope&) = delete;
        BindingScope& operator=(const BindingScope&) = delete;

        void Clear();
        void UpdateSource(Element& element) const;
        void AddRuntimeSubscription(std::function<void()> unsubscribe);
        void AddRuntimeSourceUpdate(Element& element, std::function<void()> update);
        std::shared_ptr<Element*> AddRuntimeTarget(Element& element);
        void RetargetRuntimeElement(Element& previous, Element& replacement);

        template <typename TViewModel, typename TGetter>
        void AddCommand(Element& element, TViewModel& viewModel, TGetter getter) {
            element.SetCommand(std::invoke(getter, viewModel));
        }

        template <typename TViewModel, typename TGetter, typename TSetter, typename TProperty>
        void AddOneWay(
            Element& element,
            TViewModel& viewModel,
            TGetter getter,
            TSetter setter,
            TProperty property) {
            const auto target = this->AddRuntimeTarget(element);
            const auto apply = [target, &viewModel, getter, setter]() {
                if (*target) { std::invoke(setter, **target, std::invoke(getter, viewModel)); }
            };
            apply();
            this->unsubscriptions.push_back(viewModel.Subscribe([apply, property](TProperty changedProperty) {
                if (changedProperty == property) {
                    apply();
                }
            }));
        }

        template <typename TViewModel, typename TSourceGetter, typename TSourceSetter,
            typename TTargetGetter, typename TTargetSetter, typename TProperty>
        void AddTwoWay(
            Element& element,
            TViewModel& viewModel,
            TSourceGetter sourceGetter,
            TSourceSetter sourceSetter,
            TTargetGetter targetGetter,
            TTargetSetter targetSetter,
            TProperty property) {
            this->AddOneWay(element, viewModel, sourceGetter, targetSetter, property);
            const auto target = this->AddRuntimeTarget(element);
            this->sourceUpdates.push_back({&element, [target, &viewModel, sourceSetter, targetGetter]() {
                if (*target) { std::invoke(sourceSetter, viewModel, std::invoke(targetGetter, **target)); }
            }});
        }

    private:
        struct SourceUpdate {
            Element* element = nullptr;
            std::function<void()> update;
        };

    private:
        std::vector<std::function<void()>> unsubscriptions;
        std::vector<SourceUpdate> sourceUpdates;
        std::vector<std::shared_ptr<Element*>> runtimeTargets;
    };
}