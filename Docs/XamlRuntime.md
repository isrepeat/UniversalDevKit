# XamlRuntime

XamlRuntime и OpenGLESRenderer зарегистрированы в Components.json и используют общий граф CMake/MSBuild UDK. XamlCompiler — отдельный host-инструмент в Projects/Cmake/XamlCompiler. Namespace: universaldevkit::xamlruntime, universaldevkit::xamlruntime::runtimemarkup и universaldevkit::openglesrenderer. Aliases xaml, xaml::runtime и es_renderer сохранены для перехода потребителей; новые определения namespace используют полные имена UDK.

## Общие механизмы

Геометрия находится в Helpers/Math/Geometry.h: Bounds хранит x/y/width/height, существующий Rect сохраняет left/top/right/bottom. FromEdges/ToEdges явно преобразуют представления. Contains включает границы, Intersect сохраняет пустое пересечение, Inset ограничивает размер снизу нулём. RoundOut округляет наружу и сохраняет пустоту. FitScale требует положительный исходный размер и неотрицательный конечный.

Color.h содержит RGBA и покомпонентную интерполяцию без смены цветового пространства. Motion.h содержит easing и экспоненциальное движение; нулевое затухание соответствует равномерному движению, expm1 сохраняет точность при малом шаге. Выбор анимируемого свойства, часы, пороги жестов и layout остаются в XamlRuntime.

UTF-8 объединён в Helpers/Text/Utf8.h. Unicode использует строгую проверку последовательностей, renderer заменяет повреждённые последовательности на '?'. ObservableCollection использует Helpers/Event/Signal. Отписка безопасна после уничтожения источника; новые подписки не входят в уже начатое уведомление. Текущий набор callback фиксируется Signal на начало уведомления.

Логирование использует приватную зависимость Diagnostic.Dynamic. LegacyLogging удалён. Приложение/host инициализирует Diagnostic; runtime не меняет его настройки и не вызывает Shutdown. Все модули процесса должны использовать одну Diagnostic DLL/SO и совместимый C++ runtime.

## Проверка исходников

```powershell
cmake -S Tests/XamlRuntime -B !artifacts/Windows-x64/cmake/XamlRefactor -G "Visual Studio 18 2026" -A x64
cmake --build !artifacts/Windows-x64/cmake/XamlRefactor --config Debug
ctest --test-dir !artifacts/Windows-x64/cmake/XamlRefactor -C Debug --output-on-failure
```

ColorAnimation сравнивает скомпилированную страницу и runtime-дерево, RGBA, Current, opacity и отказ при неверной разметке. Contracts проверяет геометрию, затухание, Unicode и время жизни подписок. Release проверяется той же командой с другой конфигурацией.

Для библиотеки используйте корневой CMake с UniversalDevKit_COMPONENTS=XamlRuntime либо OpenGLESRenderer. Targets: UniversalDevKit::XamlRuntime.Static/Dynamic и UniversalDevKit::OpenGLESRenderer.Static/Dynamic. Include: UniversalDevKit/XamlRuntime и UniversalDevKit/OpenGLESRenderer. MSBuild-проекты генерируются из того же реестра.

Windows renderer требует UniversalDevKitAngleRoot либо UDK_ANGLE_ROOT: установку ANGLE include/lib или распакованную прежнюю поставку с build/native/include и runtimes/win-x64/native/Release. Используются только ANGLE headers/import libraries; старые XamlRuntime-библиотеки не линкуются. На Android используется системный GLESv3. Исходники stb_truetype, NanoSVG и vcpkg recipe ANGLE находятся в ThirdParty/XamlRuntime с исходными лицензионными уведомлениями.

Android: NDK r27c, API 24+, arm64-v8a/x86_64 и c++_shared. Host-компилятор собирается отдельно под Windows. Компиляция renderer не подтверждает пиксельный результат, работу preview или запуск APK на устройстве.

Исходная точка переноса: tmp-коммит 14c8eaa, источник UtilityHelpersLib 1c12ac945f33ecab88f70756b300d4f2e8b440e5. Пакетная доставка и переход существующих приложений проверяются отдельно от контрактов исходников.