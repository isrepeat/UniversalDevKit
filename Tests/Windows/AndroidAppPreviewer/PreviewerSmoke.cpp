#include <Windows.h>

#include <AndroidAppPreviewerPluginSdk/AndroidAppPreviewerPlugin.h>

#include <stdexcept>
#include <iostream>
#include <vector>
#include <string>

int main(int argc, char** argv) {
    try {
        if (argc != 4) {
            throw std::invalid_argument("Expected template-plugin.dll, Roboto-Regular.ttf and application XAML namespace");
        }
        const auto module = ::LoadLibraryExA(argv[1], nullptr, LOAD_WITH_ALTERED_SEARCH_PATH);
        if (module == nullptr) {
            throw std::runtime_error("Plugin load failed: " + std::to_string(::GetLastError()));
        }
        using namespace universaldevkit::windows::androidapppreviewerpluginsdk;
        const auto getAbi = reinterpret_cast<const xp_plugin_abi* (*)(uint32_t)>(::GetProcAddress(module, "xp_get_abi"));
        if (getAbi == nullptr || getAbi(0) != nullptr || getAbi(1) == nullptr) {
            throw std::runtime_error("Invalid ABI negotiation");
        }
        const auto* abi = getAbi(1);
        const auto require = [abi](bool success) {
            if (!success) { throw std::runtime_error(abi->metadata.last_error()); }
        };
        // Проверяем создание прикладной сессии и доступ к навигационным данным.
        auto* session = abi->session.create(360, 800);
        require(session != nullptr);
        char initialPage[1024]{};
        require(abi->metadata.get_initial_page_id(session, initialPage, sizeof(initialPage)) != 0);
        require(abi->session.load_page(session, initialPage) != 0);
        char graph[16384]{};
        require(abi->session.preview_route_graph(session, graph, sizeof(graph)) != 0);
        require(graph[0] != 0);
        require(abi->metadata.navigate(session, "{\"transitionIds\":[\"main-to-settings\"]}") != 0);
        require(abi->metadata.navigate(session, "{\"transitionIds\":[\"settings-to-main\"]}") != 0);
        require(abi->session.load_page(session, initialPage) != 0);

        // Проверяем фактическую отрисовку приложения через поставляемый ANGLE.
        auto* surface = abi->rendering.create_angle_surface(360, 800, argv[2], "");
        require(surface != nullptr);
        std::vector<unsigned char> pixels(360 * 800 * 4);
        require(abi->session.render_angle_surface(session, surface, pixels.data(), 360 * 4, static_cast<int>(pixels.size())) != 0);
        bool hasVisiblePixels = false;
        for (std::size_t index = 3; index < pixels.size(); index += 4) {
            hasVisiblePixels |= pixels[index] != 0;
        }
        require(hasVisiblePixels);

        // Проверяем ввод, изменение размера и обработку ошибочного hot reload.
        require(abi->session.pointer_down(session, 20, 20) != 0);
        require(abi->session.pointer_up(session, 20, 20) != 0);
        require(abi->session.resize(session, 400, 800) != 0);
        require(abi->session.reload_markup(session, initialPage, "<broken", "smoke.xaml") == 0);
        require(abi->metadata.last_error()[0] != 0);
        const std::string markup = std::string("<Page xmlns=\"") + argv[3]
            + "\" background=\"#FF112233\"><TextBlock text=\"Reloaded\"/></Page>";
        require(abi->session.reload_markup(session, initialPage, markup.c_str(), "smoke.xaml") != 0);
        require(abi->session.resize(session, 360, 800) != 0);
        require(abi->session.render_angle_surface(session, surface, pixels.data(), 360 * 4, static_cast<int>(pixels.size())) != 0);
        require(pixels[0] == 0x33 && pixels[1] == 0x22 && pixels[2] == 0x11 && pixels[3] == 0xFF);
        abi->rendering.destroy_angle_surface(surface);
        abi->session.destroy(session);
        // Модуль остаётся загружен до завершения процесса: в нём зарегистрированы обработчики исключений.
        std::cout << "PASS: ABI, session, navigation, ANGLE pixels, input, resize, hot reload\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}