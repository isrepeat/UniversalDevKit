#include <UniversalDevKit/XamlRuntime/RuntimeMarkup/RuntimeTreeBuilder.h>
#include <UniversalDevKit/XamlRuntime/RuntimeMarkup/XamlParser.h>
#include <UniversalDevKit/XamlRuntime/RenderEngine.h>
#include <UniversalDevKit/XamlRuntime/Animation.h>

#include "./ColorAnimationPage.xaml.h"

#include <stdexcept>
#include <iostream>
#include <iterator>
#include <fstream>
#include <cmath>

namespace {
    void Check(bool value, const char* message) {
        if (!value) { throw std::runtime_error(message); }
    }

    void Near(float value, float expected, const char* message) {
        Check(std::abs(value - expected) < 0.0001f, message);
    }

    class Backend final : public xaml::IRenderBackend {
    public:
        float alpha = -1;
        void BeginClip(const xaml::Rect&) override {}
        void EndClip() override {}
        void DrawOutline(const xaml::Rect&, xaml::attr::Color) override {}
        void DrawRoundedRect(const xaml::Rect&, xaml::attr::Color color, float) override { alpha = color.alpha; }
        void DrawRoundedRectOutline(const xaml::Rect&, xaml::attr::Color, float, float) override {}
        void DrawShader(std::string_view, const xaml::Rect&, std::initializer_list<xaml::ShaderUniform>) override {}
        void DrawText(const xaml::Rect&, std::string_view, xaml::attr::Color, float,
            std::string_view, xaml::attr::Alignment) override {}
        void DrawImage(const xaml::Rect&, std::string_view, xaml::attr::Color) override {}
    };

    void TestColor(xaml::Element& page) {
        xaml::AnimationController controller;
        controller.Attach(page, xaml::AnimationRegistry{}, true);
        Near(page.Background().alpha, 1, "Show initial color");
        xaml::AnimationController::Update(page, std::chrono::milliseconds(500));
        Near(page.Background().alpha, (1.f + 128.f / 255.f) / 2, "Show midpoint alpha");
        Near(page.Background().red, 30.f / 255.f, "Show preserves RGB");
        xaml::AnimationController::Update(page, std::chrono::milliseconds(500));
        Near(page.Background().alpha, 128.f / 255.f, "Show final alpha");
        Check(!xaml::AnimationController::IsAnimating(page), "Show finished");
        Check(xaml::VisualStateManager::GoToState(page, "Color", "Blue"), "Color state");
        Near(page.Background().alpha, 128.f / 255.f, "Current preserves initial alpha");
        xaml::AnimationController::Update(page, std::chrono::milliseconds(500));
        Near(page.Background().red, 15.f / 255.f, "State midpoint red");
        Near(page.Background().green, 15.f / 255.f, "State midpoint green");
        Near(page.Background().blue, (30.f / 255.f + 1) / 2, "State midpoint blue");
        Near(page.Background().alpha, (128.f / 255.f + 1) / 2, "State midpoint alpha");
        xaml::AnimationController::Update(page, std::chrono::milliseconds(500));
        Near(page.Background().blue, 1, "State final blue");
        Near(page.Background().alpha, 1, "State final alpha");
    }
}

int main(int argc, char** argv) {
    try {
        Check(argc == 2, "Usage: ColorAnimationTests fixture.xaml");
        int viewModel = 0;
        xaml::BindingScope bindings;
        auto compiled = xaml::generated::ColorAnimationPage::Create(viewModel, bindings);
        TestColor(*compiled);
        std::ifstream input(argv[1]);
        const std::string markup{std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>()};
        auto runtime = xaml::runtime::RuntimeTreeBuilder{}.BuildPage(
            xaml::runtime::XamlParser{}.Parse(markup, argv[1]), {}, {100, 100});
        TestColor(*runtime.root);
        // Каждый множитель ограничивается отдельно, до композиции с альфой цвета.
        auto nested = xaml::runtime::RuntimeTreeBuilder{}.BuildPage(xaml::runtime::XamlParser{}.Parse(
            R"(<Page xmlns="urn:xaml" opacity="0.5"><Border opacity="2" background="#80FFFFFF"/></Page>)", "opacity.xaml"), {}, {100, 100});
        xaml::AnimationController nestedController;
        nestedController.Attach(*nested.root, xaml::AnimationRegistry{});
        Backend backend;
        xaml::Render(*nested.root, backend);
        Near(backend.alpha, 64.f / 255.f, "Nested opacity clamps before multiplication");
        Near(nested.root->Children().front()->Opacity(), 2, "Raw opacity remains unchanged");
        nested.root->Children().front()->States().Get<xaml::VisualTransform>().opacity = 2;
        xaml::Render(*nested.root, backend);
        Near(backend.alpha, 64.f / 255.f, "Transform opacity clamps separately");
        nested.root->Children().front()->SetOpacity(-1);
        backend.alpha = -1;
        xaml::Render(*nested.root, backend);
        Check(backend.alpha <= 0, "Negative opacity does not render visible content");
        // Ошибки разметки должны обнаруживаться до замены рабочего дерева.
        for (const auto* track : {
            R"(<ColorAnimation property="background" from="#GG112233" to="blue" duration="1"/>)",
            R"(<ColorAnimation property="opacity" from="red" to="blue" duration="1"/>)",
            R"(<ColorAnimation property="background" from="red" to="blue" duration="nan"/>)",
            R"(<ColorAnimation property="background" from="red" to="blue" duration="-1"/>)",
            R"(<ColorAnimation property="background" from="red" to="blue" duration="1" easing="Unknown"/>)"}) {
            bool rejected = false;
            try {
                const auto invalid = std::string(R"(<Page xmlns="urn:xaml"><Page.Storyboards><Storyboard trigger="Show">)")
                    + track + "</Storyboard></Page.Storyboards></Page>";
                xaml::runtime::RuntimeTreeBuilder{}.BuildPage(
                    xaml::runtime::XamlParser{}.Parse(invalid, "invalid.xaml"), {}, {100, 100});
            } catch (const std::exception&) { rejected = true; }
            Check(rejected, "Invalid ColorAnimation rejected");
        }
        std::cout << "PASS: compiled/runtime ColorAnimation, Current, RGBA interpolation, opacity clamp\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}