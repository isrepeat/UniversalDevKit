#pragma once
#if defined(ANDROID_APP_PREVIEWER)
#include <UniversalDevKit/XamlRuntime/RuntimeMarkup/RuntimeTreeBuilder.h>
#endif
#include <UniversalDevKit/XamlRuntime/XamlLayout.h>

#include "./INavigationPage.h"

namespace {{application}}::application::interface {
    class IPage : public INavigationPage {
    public:
        virtual ~IPage() = default;
        virtual std::string_view Name() const = 0;
        virtual std::string_view Title() const = 0;
        virtual void Initialize(xaml::Size availableSize) = 0;
        virtual void Update() = 0;
        virtual xaml::Element& Root() = 0;
#if defined(ANDROID_APP_PREVIEWER)
        virtual xaml::runtime::RuntimeBindingContext preview_RuntimeContext() = 0;
        virtual void preview_ReplaceRuntimeTree(xaml::runtime::RuntimeBuildResult runtimeBuildResult) = 0;
#endif
    };
}