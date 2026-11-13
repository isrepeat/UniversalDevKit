#include "../../Includes/XamlRuntime/UniversalDevKit/XamlRuntime/UserControl.h"

#include "../../Includes/XamlRuntime/UniversalDevKit/XamlRuntime/Binding.h"

#include <stdexcept>

namespace universaldevkit::xamlruntime {
    UserControl::UserControl()
        : Element(ElementType::grid) {
    }

    UserControl::~UserControl() {
        this->ClearContentBindings();
    }

    Element* UserControl::Content() const {
        return this->content;
    }

    void UserControl::InitializeComponent(
        std::unique_ptr<Element> root,
        std::unique_ptr<BindingScope> bindings) {
        if (!root || !bindings || this->content) {
            throw std::logic_error("UserControl content can only be initialized once");
        }
        this->contentBindings = std::move(bindings);
        this->content = root.get();
        this->AddChild(std::move(root));
        this->OnInitialized();
    }

    void UserControl::ReplaceContent(
        std::unique_ptr<Element> root,
        std::unique_ptr<BindingScope> bindings) {
        if (!root || !bindings) {
            throw std::invalid_argument("UserControl replacement requires content and bindings");
        }
        // The old binding scope must be released before the old tree.
        this->ClearContentBindings();
        Element* const previous = this->content;
        this->AddChild(std::move(root));
        this->content = this->Children().back().get();
        if (previous != nullptr) {
            this->RemoveChildImmediately(*previous);
        }
        this->contentBindings = std::move(bindings);
    }

    void UserControl::ClearContentBindings() {
        // Element destroys its child Content in its destructor. First remove
        // callbacks that might retain pointers to elements in that tree.
        this->contentBindings.reset();
    }

    void UserControl::OnInitialized() {
    }
}