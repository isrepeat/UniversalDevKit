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
        // Старый scope должен исчезнуть раньше, чем удаляется прежнее дерево.
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
        // Element уничтожит дочерний Content в своём деструкторе. Сначала снимаем
        // callbacks, которые могут хранить указатели на элементы этого дерева.
        this->contentBindings.reset();
    }

    void UserControl::OnInitialized() {
    }
}