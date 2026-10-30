# XamlRuntime: временный перенос (tmp)

Исходники перенесены из UtilityHelpersLib, commit 1c12ac945f33ecab88f70756b300d4f2e8b440e5. Это исходная точка для следующих отдельных коммитов: перенос общей математики в Helpers/Math, переход на Diagnostic, адаптация реестра компонентов и пакетных поставок.

## Состав

- Includes/XamlRuntime/UniversalDevKit/XamlRuntime — заголовки runtime; Sources/XamlRuntime — реализация.
- Includes/OpenGLESRenderer/UniversalDevKit/OpenGLESRenderer — заголовки renderer; Sources/OpenGLESRenderer — реализация.
- Sources/XamlCompiler/Main.cpp — host-компилятор XAML; Projects/Cmake/XamlCompiler — его самостоятельная сборка.
- ThirdParty/XamlRuntime — исходные stb_truetype, NanoSVG и ANGLE vcpkg recipes. Лицензионные уведомления внутри файлов сохранены. Готовые ANGLE-бинарники не включены.
- Sources/XamlRuntime/LegacyLogging — временная приватная копия Helpers.Logging с исходными Windows/Android backend. Она использует существующий ThirdParty/spdlog UDK в header-only режиме. Это не Diagnostic и не новый публичный компонент.
- Tests/XamlRuntime — существующая проверка ColorAnimation и её разметка.

Поведение layout, binding, анимаций, clipping, цветов и жестов сохраняется. Namespace xaml/es_renderer и старые имена сущностей пока сохранены намеренно. Публичные include переведены на UniversalDevKit/XamlRuntime и UniversalDevKit/OpenGLESRenderer; host-компилятор генерирует новые include. Внутренние include пересчитаны после разделения заголовков и реализации. Переформатирование и исправления алгоритмов отложены; этот tmp-коммит не является завершением миграции.

## Сборка Windows

Временный CMake-проект независим от корневого Components.json: он создаёт только исходные статические библиотеки и host-инструмент, не объявляя ещё не адаптированные Dynamic/Shared варианты и пакетные контракты. Общая сборка UDK не изменена. Visual Studio использует сгенерированные CMake проекты внутри !artifacts.

```powershell
cmake -S Projects/Cmake/XamlRuntime -B !artifacts/Windows-x64/cmake/XamlRuntimeTmp -G "Visual Studio 18 2026" -A x64 -DUniversalDevKitXaml_BUILD_RENDERER=OFF
cmake --build !artifacts/Windows-x64/cmake/XamlRuntimeTmp --config Debug
ctest --test-dir !artifacts/Windows-x64/cmake/XamlRuntimeTmp -C Debug --output-on-failure
```

Для renderer включите UniversalDevKitXaml_BUILD_RENDERER и передайте UniversalDevKitXaml_ANGLE_ROOT: каталог установки ANGLE с include/lib либо распакованный старый XamlRuntime NuGet с build/native/include и runtimes/win-x64/native/Release. Используются только ANGLE headers/import libraries, библиотеки старого XamlRuntime не подключаются. Renderer сейчас собирается как static archive; для его запуска приложению отдельно нужны совместимые ANGLE DLL и их runtime-зависимости. Автоматическая сборка и доставка ANGLE появятся при адаптации пакетов.

Targets: UniversalDevKit::XamlRuntime.Static, UniversalDevKit::OpenGLESRenderer.Static. Старые XamlRuntime::Runtime и XamlRuntime::OpenGLESRenderer сохранены как CMake aliases. Потребитель может подключить Projects/Cmake/XamlRuntime через add_subdirectory; параметры compiler/tests при этом следует отключить, если инструменты не нужны.

## Android

Используйте штатный NDK r27c toolchain, ABI arm64-v8a или x86_64, API 24 и c++_shared. При cross-build обязательно отключите UniversalDevKitXaml_BUILD_COMPILER и UniversalDevKitXaml_BUILD_TESTS: host-компилятор собирается отдельно под Windows. Android renderer использует системный GLESv3; legacy logging использует logcat.

Начальная проверка: Windows Debug/Release с выполнением существующего ColorAnimation-теста и Android native-сборка. Она не подтверждает пиксельный результат renderer, preview, APK или работу на Android-устройстве. NuGet/AAR публикация, переход потребителей и удаление старой реализации здесь не выполняются.