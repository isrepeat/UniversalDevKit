#include "../../../Includes/XamlRuntime/UniversalDevKit/XamlRuntime/RuntimeMarkup/RuntimeReloadTransaction.h"

#include "../../../Includes/XamlRuntime/UniversalDevKit/XamlRuntime/RuntimeMarkup/RuntimeDiagnostics.h"
#include "../../../Includes/XamlRuntime/UniversalDevKit/XamlRuntime/RuntimeMarkup/XamlParser.h"

namespace universaldevkit::xamlruntime::runtimemarkup {
    namespace details {
        void Collect(const Element& node, std::map<std::string, const Element*>& elements) {
            if (!node.Id().empty()) {
                elements.emplace(node.Id(), &node);
            }
            for (const auto& child : node.Children()) {
                Collect(*child, elements);
            }
        }

        void Restore(Element& node, const std::map<std::string, const Element*>& elements) {
            const auto found = elements.find(node.Id());
            if (found != elements.end() && found->second->Type() == node.Type()) {
                node.SetHorizontalOffset(found->second->HorizontalOffset());
                node.SetVerticalOffset(found->second->VerticalOffset());
                if (found->second->HasSelectedWireframe()) {
                    node.SetSelectedWireframe(found->second->SelectedWireframe());
                }
            }
            for (const auto& child : node.Children()) {
                Restore(*child, elements);
            }
        }
    } // namespace details

    //
    // API
    //
    RuntimeBuildResult RuntimeReloadTransaction::Prepare(std::string_view markup, std::string_view sourcePath,
        const RuntimeBindingContext& context, const Element& previous, Size availableSize) {
        const auto ast = XamlParser{}.Parse(markup, sourcePath);
        if (ast.name != "Page" || ast.nameSpace != context.xamlNamespace) {
            throw RuntimeDiagnostic(ast.location, "Page markup requires a Page root");
        }
        auto result = RuntimeTreeBuilder{}.BuildPage(ast, context, availableSize);
        // The host page supplies DataContext, preventing hot-reloaded XAML
        // from replacing the ViewModel.
        result.root->SetDataContext(previous.DataContext());
        std::map<std::string, const Element*> elements;
        details::Collect(previous, elements);
        // Transfer state only between elements with matching names and types.
        // State from the old control may be incompatible with the new one.
        details::Restore(*result.root, elements);
        result.root->SetVisibility(previous.VisibilityValue());
        layout(*result.root, availableSize);
        return result;
    }
}