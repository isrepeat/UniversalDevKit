#pragma once
#include "XamlLayout.h"

#include <memory>

namespace xaml {
    class UserControl : public Element {
    public:
        UserControl();
        ~UserControl() override;

        Element* Content() const;

    protected:
        void InitializeComponent(std::unique_ptr<Element> root, std::unique_ptr<BindingScope> bindings);
        void ReplaceContent(std::unique_ptr<Element> root, std::unique_ptr<BindingScope> bindings);
        void ClearContentBindings();
        virtual void OnInitialized();

    private:
        Element* content = nullptr;
        // Scope существует ровно столько же, сколько текущее дерево Content.
        std::unique_ptr<BindingScope> contentBindings;
    };
}