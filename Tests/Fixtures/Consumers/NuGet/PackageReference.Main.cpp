#if defined(UDK_TEST_XAML)
#include <UniversalDevKit/XamlRuntime/RuntimeMarkup/RuntimeTreeBuilder.h>
#include <UniversalDevKit/XamlRuntime/RuntimeMarkup/XamlParser.h>
#if defined(UDK_TEST_RENDERER)
#include <UniversalDevKit/OpenGLESRenderer/OpenGlRenderer.h>
#endif
#elif defined(UDK_TEST_DIAGNOSTIC)
#include <UniversalDevKit/Diagnostic/Logging.h>
#if !defined(UNIVERSALDEVKIT_DIAGNOSTIC_DYNAMIC)
#error Diagnostic dynamic import definition is missing
#endif
#if __has_include(<UniversalDevKit/Helpers/System/Thread.h>) || __has_include(<spdlog/spdlog.h>)
#error Private logger dependencies leaked into consumer
#endif
#elif defined(UDK_TEST_HEADER_HELPERS)
#include <UniversalDevKit/Helpers/Math/Tensor.h>
#include <UniversalDevKit/Helpers/Meta/Utilities/ValueExtractor.h>
#elif !defined(UDK_TEST_HELEPRSTEST_ONLY)
#include <UniversalDevKit/DiagnosticTest/Logging.h>
#if defined(UDK_TEST_DYNAMIC) && !defined(UNIVERSALDEVKIT_DIAGNOSTICTEST_DYNAMIC)
#error DiagnosticTest dynamic import definition is missing
#endif
#if defined(UNIVERSALDEVKIT_HELEPRSTEST_DYNAMIC) || __has_include(<UniversalDevKit/HeleprsTest/Text.h>)
#error Private HeleprsTest requirements leaked into consumer
#endif
#else
#include <UniversalDevKit/HeleprsTest/Text.h>
#if defined(UDK_TEST_DYNAMIC) && !defined(UNIVERSALDEVKIT_HELEPRSTEST_DYNAMIC)
#error HeleprsTest dynamic import definition is missing
#endif
#endif

#include <iostream>
#if defined(UDK_TEST_DIAGNOSTIC)
#include <fstream>
#include <string>
#endif

int main() {
#if defined(UDK_TEST_XAML)
#if defined(UDK_TEST_RENDERER)
    volatile auto rendererEntry = &es_renderer::OpenGlRenderer::BeginFrame;
    (void)rendererEntry;
#endif
    const auto tree = xaml::runtime::XamlParser{}.Parse(R"(<Page xmlns="urn:xaml" background="red"/>)", "package.xaml");
    auto page = xaml::runtime::RuntimeTreeBuilder{}.BuildPage(tree, {}, {100, 100});
    if (!page.root || page.root->Background().red != 1) { return 1; }
#elif defined(UDK_TEST_DIAGNOSTIC)
    using universaldevkit::diagnostic::Logger;
    universaldevkit::diagnostic::LoggerOptions loggerOptions;
    loggerOptions.filePath = "diagnostic-package.log";
    loggerOptions.fileMode = universaldevkit::diagnostic::FileMode::Truncate;
    loggerOptions.appendNewSession = false;
    if (!Logger::Initialize(loggerOptions)) { return 1; }
    Logger::Write(universaldevkit::diagnostic::Level::Info, "Package", "Diagnostic package passed");
    Logger::Shutdown();
    std::ifstream stream(loggerOptions.filePath);
    std::string line;
    if (!std::getline(stream, line) || line.find("Diagnostic package passed") == std::string::npos) { return 2; }
#elif defined(UDK_TEST_HEADER_HELPERS)
    universaldevkit::helpers::math::Mat2x2f matrix;
    matrix[1][1] = 42.0f;
    float* value = &matrix[1][1];
    if (universaldevkit::helpers::meta::utilities::ValueExtractor::From(value) != 42.0f) { return 1; }
#elif defined(UDK_TEST_HELEPRSTEST_ONLY)
    if (!universaldevkit::heleprstest::text::EndsWithLineBreak("test\n")) { return 1; }
#else
    if (!universaldevkit::diagnostictest::TryLog("PackageReference consumer passed")) { return 1; }
#endif
    std::cout << "PackageReference consumer passed\n";
    return 0;
}