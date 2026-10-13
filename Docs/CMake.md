# Сборка через CMake

**Навигация:** [Главная](../README.md) → [Документация](README.md) → CMake

## Содержание

- [Конфигурация и сборка — разные этапы](#конфигурация-и-сборка--разные-этапы)
- [Подключить checkout к приложению](#подключить-checkout-к-приложению)
- [Выбрать состав сборки](#выбрать-состав-сборки)
- [Что делает ComponentDependencies.cmake](#что-делает-componentdependenciescmake)
- [Установить пакет](#установить-пакет)
- [Подключить установленный пакет](#подключить-установленный-пакет)
- [Ограничения и проверка](#ограничения-и-проверка)

## Конфигурация и сборка — разные этапы

CMake версии 3.22 или выше читает описания и генерирует систему сборки. cmake --build запускает компилятор и линкер через выбранный генератор. Корневой проект требует C++17.

Для Windows x64 в среде с настроенными MSVC и Ninja:

```powershell
cmake --preset windows-x64
cmake --build --preset windows-x64-release
```

Preset использует Ninja Multi-Config. Debug/Release выбирается при сборке, а каталог конфигурации общий. Самостоятельная конфигурация UDK должна находиться внутри !artifacts; для add_subdirectory это ограничение не действует.

## Подключить checkout к приложению

```cmake
add_subdirectory(external/UniversalDevKit)
target_link_libraries(MyApplication PRIVATE UniversalDevKit::Diagnostic.Static)
```

Targets передают include-путь, минимальный стандарт языка и необходимые зависимости. Diagnostic.Static требует Helpers.Static; вручную повторять эту связь не нужно.

Для динамического варианта используйте UniversalDevKit::Diagnostic.Dynamic. На Windows consumer получает import-макрос; DLL должна быть доступна при запуске. Например, для CMake 3.22 и известного набора runtime DLL:

```cmake
if(WIN32)
    add_custom_command(TARGET MyApplication POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            $<TARGET_RUNTIME_DLLS:MyApplication> $<TARGET_FILE_DIR:MyApplication>
        COMMAND_EXPAND_LISTS
    )
endif()
```

Этот пример применяют при наличии DLL-зависимостей. Для Linux/Android доставка SO и пути загрузчика настраиваются по правилам целевой платформы; MSBuild runtime-target в CMake не используется.

## Выбрать состав сборки

| Настройка | По умолчанию | Значение |
|---|---|---|
| UniversalDevKit_COMPONENTS | ALL | Корневые компоненты через `;`; пустая строка исключает все корни |
| UniversalDevKit_BUILD_STATIC | ON | Создавать статические варианты корней |
| UniversalDevKit_BUILD_DYNAMIC | ON | Создавать динамические варианты корней |
| UniversalDevKit_INSTALL | ON | Создавать правила установки |

Пример конфигурации только Diagnostic.Dynamic:

```powershell
cmake --preset windows-x64 -DUniversalDevKit_COMPONENTS=Diagnostic -DUniversalDevKit_BUILD_STATIC=OFF
```

Helpers.Static всё равно создаётся, поскольку JSON требует его для Diagnostic.Dynamic. BUILD_STATIC=OFF запрещает статические варианты корней, но не обязательных зависимостей. Для шаблонного кода используйте UniversalDevKit::Helpers.Headers или другой компонентный Headers-target: он предоставляет свой include-корень и публичные зависимости. UniversalDevKit::Headers предоставляет только общие Export.h и Version.h. При установке копируются заголовки выбранных бинарных компонентов и их зависимостей; компонентные Headers-targets экспортируются вместе с ними.

При add_subdirectory настройки можно задать заранее как обычные переменные при стандартной политике CMake родительского проекта. Выбор в меню Connect этих настроек не меняет.

## Что делает ComponentDependencies.cmake

Корневой CMakeLists включает Projects/Cmake/ComponentDependencies.cmake. Модуль читает JSON, раскрывает необходимые варианты и проверяет неизвестные компоненты, циклы и поддерживаемую ОС. Затем создаёт библиотеки из общих и платформенных файлов, добавляет alias targets, определения и настройки экспорта.

После создания targets применяются межкомпонентные связи PUBLIC/PRIVATE и same/static/dynamic. ComponentRequirements.cmake читает стандарт C++, потоки и системные библиотеки из JSON; установленный пакет получает необходимые find_dependency. Подробнее — [Requirements](Requirements.md). Необязательный Projects/Cmake/<компонент>/CMakeLists.txt расширяет созданные варианты через currentComponentTargets для требований, которых пока нет в общем формате.

Сам consumer этот модуль напрямую не включает. Изменения JSON отслеживаются через CMAKE_CONFIGURE_DEPENDS и вызывают переконфигурацию сборочного дерева.

## Установить пакет

После сборки выбранной конфигурации:

```powershell
cmake --install "!artifacts/Windows-x64/cmake/msvc-$env:VCToolsVersion-md/UniversalDevKit" --config Release
```

Preset задаёт prefix установки внутри этого дерева, в install/. Для другой цели используйте --prefix. Пакет содержит include/, библиотеки и конфигурацию в `<libdir>/cmake/UniversalDevKit/`; libdir выбирается GNUInstallDirs. На Windows DLL находятся в bin/.

UniversalDevKitRuntime=Dynamic задаёт /MD (/MDd в Debug), Static — /MT (/MTd в Debug). Настройка применяется к targets UDK и не меняет глобальный CRT consumer. Явный CMAKE_MSVC_RUNTIME_LIBRARY должен соответствовать выбранному CRT. Для разных CRT и toolchains используйте разные build/install-каталоги: UDK сохраняет идентификатор компилятора, архитектуры и CRT и отклоняет изменение варианта в существующем build-каталоге. Preset windows-x64 использует дерево msvc-<VCToolsVersion>-md; запускайте его из Developer PowerShell с заданной VCToolsVersion. Проверка CRT уже установленного пакета остаётся следующим этапом.

Debug-имена бинарников имеют суффикс d, поэтому Debug и Release можно устанавливать в один prefix без перезаписи библиотек. Обе конфигурации нужно предварительно собрать и установить; пакет не создаёт отсутствующую конфигурацию автоматически.

## Подключить установленный пакет

В отдельном consumer:

```cmake
find_package(UniversalDevKit 0.1 CONFIG REQUIRED COMPONENTS Diagnostic)
target_link_libraries(MyApplication PRIVATE UniversalDevKit::Diagnostic.Static)
```

При конфигурации укажите CMAKE_PREFIX_PATH с корнем установки либо UniversalDevKit_DIR с каталогом конфигурации пакета. find_package загружает экспортированные targets с путями и usage requirements; исходный checkout и ComponentDependencies.cmake не нужны.

COMPONENTS проверяет наличие компонента в установленном наборе, но не выбирает Static/Dynamic: вариант выбирается именем target. Конфигурация загружает весь установленный экспорт, а не только перечисленные COMPONENTS. Unknown или исключённый обязательный компонент должен отклоняться.

SameMinorVersion ограничивает совместимость версии в пределах 0.1.x. ARCH_INDEPENDENT удалён, стандартная архитектурная проверка версии включена. Это не полная проверка ABI: совместимость toolchain и CRT остаётся отдельным требованием.

## Ограничения и проверка

UDK передаёт через COMPATIBLE_INTERFACE_STRING требования вариантов всех компонентов графа, включая внутренние зависимости DLL. При генерации CMake отклоняет несовместимые Static/Dynamic у одного consumer. Проверка работает и через add_subdirectory, и через установленный пакет. Разные независимые consumer могут выбирать разные варианты.

Установленные бинарные targets используют точное соответствие конфигураций: Debug не подменяется Release. Для multi-config consumer перечислите только установленные конфигурации, например `-DCMAKE_CONFIGURATION_TYPES="Debug;Release"`. Для single-config задайте CMAKE_BUILD_TYPE. Если используемому target не хватает выбранной конфигурации, генерация завершается ошибкой. Это также относится к RelWithDebInfo/MinSizeRel: требуемый вариант нужно собрать и установить отдельно.

Режимы и платформенный реестр не заменяют toolchain. Встроенный preset проверен только на Windows x64. Стандартная проверка версии отклоняет несовпадение разрядности (проверено x64 → Win32), но не является полной матрицей ISA, CRT и ABI.

Проверка переноса пакета, запуска Static/Dynamic и ограничений описана в [Validation](Validation.md). Схема JSON и расширения компонентных настроек — в [Components](Components.md).