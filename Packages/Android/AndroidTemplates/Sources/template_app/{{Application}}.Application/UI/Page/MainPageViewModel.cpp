#include "MainPageViewModel.h"

#if defined(ANDROID_APP_PREVIEWER)
#include <UniversalDevKit/XamlRuntime/RuntimeMarkup/RuntimeBindingRegistry.h>
#endif

#include "../../Core/NavigationStates.h"
#include "../../../!Generated/Build/BuildVersion.h"
#include "../../../!Generated/{{Application}}.Application/Xaml/Page/MainPage.xaml.h"

#include <utility>

namespace {{application}}::application::ui::page {
    MainPageViewModel::MainPageViewModel(core::PageContext& pageContext)
        : pageContext(pageContext)
        , packageVersion("Version " {{APPLICATION}}_PACKAGE_VERSION) {
    }

    //
    // INavigationPage
    //
    std::unique_ptr<base::NavigationStateBase> MainPageViewModel::OnNavigatingFrom(const core::NavigationRequest&) {
        return {};
    }

    bool MainPageViewModel::OnNavigatingTo(const core::NavigationRequest&, std::unique_ptr<base::NavigationStateBase> navigationState) {
        return navigationState == nullptr;
    }

    //
    // IPage
    //
    std::string_view MainPageViewModel::Name() const {
        return PageName;
    }

    std::string_view MainPageViewModel::Title() const {
        return "Main";
    }

    void MainPageViewModel::Initialize(xaml::Size availableSize) {
        this->bindings = std::make_unique<xaml::BindingScope>();
        this->root = xaml::generated::MainPage::Create(*this, *this->bindings);
        xaml::layoutInViewport(*this->root, availableSize);
    }

    void MainPageViewModel::Update() {
        if (this->status != this->pageContext.appSessionController.Status()) {
            this->status = this->pageContext.appSessionController.Status();
            for (const auto& [id, handler] : this->handlers) {
                handler(Property::status);
            }
        }
    }

    xaml::Element& MainPageViewModel::Root() {
        return *this->root;
    }
#if defined(ANDROID_APP_PREVIEWER)
    xaml::runtime::RuntimeBindingContext MainPageViewModel::preview_RuntimeContext() {
        xaml::runtime::RuntimeBindingContext result;
        result.xamlNamespace = "urn:{{application}}:xaml";
        result.owner = PageName;
        result.bindings = std::make_shared<xaml::runtime::RuntimeBindingRegistry>();
        result.bindings->AddCommand("NavigateToSettingsCommand", this->NavigateToSettingsCommand());
        result.bindings->AddText("PackageVersion", [this] { return this->PackageVersion(); });
        result.bindings->AddCommand("RequestApplicationUpdateCommand", this->RequestApplicationUpdateCommand());
        result.bindings->AddCommand("SendLogsCommand", this->SendLogsCommand());
        result.bindings->AddText("Status", [this] { return this->Status(); }, [this](std::function<void()> handler) {
            return this->Subscribe([handler](Property) { handler(); });
        });
        return result;
    }

    void MainPageViewModel::preview_ReplaceRuntimeTree(xaml::runtime::RuntimeBuildResult runtimeBuildResult) {
        this->bindings = std::move(runtimeBuildResult.bindings);
        this->root = std::move(runtimeBuildResult.root);
    }
#endif
    //
    // API
    //
    xaml::Element::Command MainPageViewModel::NavigateToSettingsCommand() {
        return [this] {
            auto greetingNavigationState = std::make_unique<core::GreetingNavigationState>();
            greetingNavigationState->Message = this->pageContext.applicationRepository.Greeting();
            this->pageContext.navigator.Trigger(
                core::NavigationTrigger::navigateToSettings,
                std::move(greetingNavigationState));
        };
    }
    xaml::Element::Command MainPageViewModel::RequestApplicationUpdateCommand() {
        return [this] {
            this->pageContext.hostCommands.Dispatch(core::HostCommand::requestApplicationUpdate);
            this->Update();
        };
    }

    xaml::Element::Command MainPageViewModel::SendLogsCommand() {
        return [this] {
            this->pageContext.hostCommands.Dispatch(core::HostCommand::sendLogs);
            this->Update();
        };
    }

    const std::string& MainPageViewModel::Status() const {
        return this->status;
    }

    const std::string& MainPageViewModel::PackageVersion() const {
        return this->packageVersion;
    }

    std::function<void()> MainPageViewModel::Subscribe(PropertyChangedHandler propertyChangedHandler) {
        const size_t id = ++this->nextSubscription;
        this->handlers.emplace(id, std::move(propertyChangedHandler));
        return [this, id] { this->handlers.erase(id); };
    }
}