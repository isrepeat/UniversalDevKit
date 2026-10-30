#pragma once
#include "RuntimeBindingRegistry.h"

#include <functional>
#include <utility>
#include <string>

namespace xaml::runtime {
    // Объединяет повторяющуюся механику runtime-байндинга с контрактом ViewModel:
    // получение значения, подписка на Property и отписка вместе с BindingScope.
    template <typename TViewModel>
    class RuntimeBindingPublisher final {
    public:
        RuntimeBindingPublisher(RuntimeBindingRegistry& registry, TViewModel& viewModel)
            : registry(registry)
            , viewModel(viewModel) {
        }

        template <typename TProperty, typename TGetter>
        void Text(std::string name, TProperty property, TGetter getter) {
            TViewModel* const viewModel = &this->viewModel;
            this->registry.AddText(std::move(name), [viewModel, getter]() {
                return (viewModel->*getter)();
            }, this->Subscription(property));
        }

        template <typename TProperty, typename TGetter>
        void Boolean(std::string name, TProperty property, TGetter getter) {
            TViewModel* const viewModel = &this->viewModel;
            this->registry.AddBoolean(std::move(name), [viewModel, getter]() {
                return (viewModel->*getter)();
            }, this->Subscription(property));
        }

        template <typename TProperty, typename TGetter, typename TSetter>
        void Boolean(std::string name, TProperty property, TGetter getter, TSetter setter) {
            TViewModel* const viewModel = &this->viewModel;
            this->registry.AddBoolean(std::move(name), [viewModel, getter]() {
                return (viewModel->*getter)();
            }, this->Subscription(property), [viewModel, setter](bool value) {
                (viewModel->*setter)(value);
            });
        }

        template <typename TGetter>
        void Command(std::string name, TGetter getter) {
            this->registry.AddCommand(std::move(name), (this->viewModel.*getter)());
        }

    private:
        template <typename TProperty>
        SubscriptionFactory Subscription(TProperty property) {
            TViewModel* const viewModel = &this->viewModel;
            return [viewModel, property](std::function<void()> changed) {
                return viewModel->Subscribe([property, changed](TProperty changedProperty) {
                    if (changedProperty == property) {
                        changed();
                    }
                });
            };
        }

    private:
        RuntimeBindingRegistry& registry;
        TViewModel& viewModel;
    };
}