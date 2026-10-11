# UniversalDevKit

Общие C++-хелперы для Windows, Linux и Android. Минимальная версия языка — C++17.

## Структура

- `Includes/UniversalDevKit/` — единственный экземпляр публичных заголовков и шаблонной реализации, разделённых по компонентам: `Helpers/`, `Diagnostic/` и другие.
- `Sources/` — компилируемая реализация и внутренние заголовки с тем же деревом компонентов, без дополнительного уровня `UniversalDevKit/`.
- `Projects/Cmake/` — интеграция установленного CMake-пакета.
- `Projects/MsBuild/` — проект для Visual Studio и публичные настройки подключения.
- `UniversalDevKit.sln` — solution с конфигурациями Debug и Release для x64.

Для Helpers и Diagnostic solution содержит `.Shared`, `.Static` и `.Dynamic`. C++ Shared Project представлен файлом `.vcxitems`: он хранит единственный список исходников MSBuild и их фильтры, самостоятельно библиотеку не собирает. Static и Dynamic импортируют этот список и создают соответственно статическую библиотеку и DLL. Исходники остаются в `Includes/` и `Sources/` без копирования. Общие настройки отображаются один раз в папке Build на уровне solution.

CMake предоставляет targets `UniversalDevKit::Helpers.Static`, `UniversalDevKit::Helpers.Dynamic`, `UniversalDevKit::Diagnostic.Static` и `UniversalDevKit::Diagnostic.Dynamic`. `UniversalDevKit::Headers` сохраняется для шаблонного кода. Helpers содержит `Square` и компилируемую функцию `IsPowerOfTwo`; Diagnostic содержит минимальную потокобезопасную запись строки в `std::clog` через `diagnostic::Log`.

В MSBuild потребителю DLL нужны импортная библиотека, DLL при запуске и определение `UNIVERSALDEVKIT_HELPERS_DYNAMIC` или `UNIVERSALDEVKIT_DIAGNOSTIC_DYNAMIC` для соответствующего компонента. Определения с суффиксом `_EXPORTS` используются только при сборке DLL. CMake передаёт публичные определения автоматически. Не подключайте Static, Dynamic и исходники одного компонента одновременно.

## Подключение через CMake

```cmake
add_subdirectory(external/UniversalDevKit)
target_link_libraries(MyApplication PRIVATE UniversalDevKit::Helpers.Static UniversalDevKit::Diagnostic.Static)
```

Также поддерживаются `cmake --install` и подключение установленного пакета через `find_package(UniversalDevKit CONFIG REQUIRED)`.

## Подключение через MSBuild

Для подключения компонентов из submodule или отдельного checkout запустите двойным кликом `Scripts/Connect.cmd`. Укажите путь к `.sln` потребителя или папке с решениями, затем выберите решение и проект. Единственный consumer выбирается автоматически. Выберите Connect / update или Disconnect. В меню Connect стрелки вверх/вниз выбирают компонент, влево/вправо — Shared, Static или Dynamic, Space отмечает режим. На компонент допускается одна отметка; уже подключённые показывают текущий режим. Enter на Apply применяет выбор, Esc отменяет операцию до записи изменений. Connect добавляет компоненты или переключает их режимы; снятие отметки оставляет прежнее подключение без изменений. Disconnect предлагает подключённые компоненты с текущими режимами и удаляет только отмеченные. Скрипт подключает публичные настройки заголовков, Shared References или Project References; для Dynamic задаёт import-макрос API и копирует DLL рядом с приложением. Неиспользуемые проекты UniversalDevKit и пустые папки очищаются, зависимости других consumer сохраняются. Варианты зависимостей рассчитываются по JSON; несовместимые варианты одного компонента блокируются до записи. После изменения перезагрузите solution в Visual Studio.

Подробные сценарии Shared/Static/Dynamic, правила зависимостей, конфликты вариантов и обновление consumer описаны в [Connect.README.md](Scripts/PowerShell/Connect.README.md).

Connect предлагает компоненты из сгенерированного реестра компонентов или все компоненты. В Shared их `.cpp` и транзитивные зависимости из JSON компилируются непосредственно в проекте потребителя; каждый компонент добавляется один раз. PCH потребителя для этих файлов отключён, объектные файлы имеют отдельные пути внутри `$(IntDir)UniversalDevKit/`. Static/Dynamic учитывают visibility/linkage зависимостей, передают необходимые библиотеки линкеру и копируют транзитивные DLL по фактическому TargetPath. После изменения реестра компонентов запустите GenerateComponentProjects.cmd и повторите Connect: отпечатки JSON обнаруживают устаревшее подключение до компиляции. Для нескольких проектов повторите подключение с выбором каждого потребителя. Изменённые `.sln` и `.vcxproj` сохраняются в Git потребителя.

Для специального подключения только к проекту используйте `Connect.ps1 -ProjectOnly -ProjectPath <consumer.vcxproj> -Components Helpers`. Этот режим использует `Sources.targets` и не изменяет solution; зависимости обновляются при сборке. Обычный сценарий командной строки — `Connect.ps1 -SolutionPath <consumer.sln> -ProjectPath <consumer.vcxproj> -Components Helpers`; ProjectPath можно опустить при единственном consumer. Параметры можно передавать также через Connect.cmd.

Импортируйте после `Microsoft.Cpp.props` в C++-проекте потребителя:

```xml
<Import Project="..\external\UniversalDevKit\Projects\MsBuild\UniversalDevKit.props" />
```

Потребитель выбирает C++17 или более новый стандарт самостоятельно. Импорт добавляет путь к заголовкам и сохраняет существующие include-пути. Открытие solution не заменяет этот импорт в другом проекте.

## Использование

```cpp
#include <UniversalDevKit/Helpers/Math.h>

namespace udk = universaldevkit;
static_assert(udk::math::Square(5) == 25);
```

`Square` использует обычное умножение типа аргумента и не проверяет переполнение.

## Артефакты сборки

Все результаты сборки располагаются в `!artifacts/<ОС>-<архитектура>/<система сборки>/<проект>/`. После платформы идёт `cmake/` или `msbuild/`, затем имя проекта. MSBuild далее использует `<конфигурация>/bin/` и `<конфигурация>/obj/`. Установленный CMake-пакет располагается в `install/`.

Для CMake на Windows x64 используйте preset `windows-x64` из среды разработки с настроенными MSVC и Ninja: `cmake --preset windows-x64`, затем `cmake --build --preset windows-x64-release`. При ручной конфигурации передавайте `-B !artifacts/<ОС>-<архитектура>/cmake/<проект>`. Другие платформы получат отдельные presets при добавлении их проверенной конфигурации сборки.

`Projects/MsBuild/BuildLayout.props` задаёт каталоги только для собственных проектов репозитория; публичный `UniversalDevKit.props` не меняет каталоги потребителя.

## Расширение

Публичный namespace — `universaldevkit`. Заголовки компонента находятся в `Includes/UniversalDevKit/<компонент>/`, его компилируемая реализация и внутренние заголовки — в `Sources/<компонент>/`. Например, публичный `Includes/UniversalDevKit/Diagnostic/Logging.h` соответствует реализации `Sources/Diagnostic/Logging.cpp`. Потребителю передаётся только корень `Includes/`; публичный путь подключения — `<UniversalDevKit/Diagnostic/Logging.h>`. Шаблоны остаются в заголовках; обычные функции Math реализованы в `Sources/Helpers/Math.cpp`. Каталоги компонентов создаются по мере появления кода.

CMake и MSBuild используют одни исходники. Платформенные реализации располагаются в `Sources/<компонент>/platform/<платформа>/` и выбираются явно для каждой поддерживаемой платформы. Физические каталоги компонентов не требуют отдельной библиотеки для каждой папки. Описание упаковки NuGet и Android добавляется в `PackageProjects/`, готовые пакеты не хранятся в Git.

## Правила изменений

### Дерево файлов Visual Studio

В `Projects/Components/*.json` поле `filters.roots` задаёт замену корней виртуальных папок, а `filters.files` — исключения для конкретных файлов. Подкаталоги ниже выбранного корня сохраняются. Пустые корневые фильтры объединяют заголовки и реализации. Физические файлы не перемещаются.

`Scripts/PowerShell/GenerateComponentProjects.ps1` формирует `.vcxitems` из JSON, затем вызывает внутренний `UpdateProjectFilters.ps1`, который формирует `.filters` для `.vcxproj` и `.vcxitems` вне каталогов артефактов. Список файлов берётся из проектов, виртуальные папки компонентов — из сгенерированных метаданных. Для остальных проектов сохраняется поддержка `UniversalDevKitFilterRoots`.

Запустите двойным кликом `Scripts\GenerateComponentProjects.cmd`: он обновляет проекты и фильтры, выводит статус и ожидает нажатия клавиши. Неизменившиеся файлы не перезаписываются. После завершения перезагрузите проект или solution в Visual Studio. Для проверки обоих этапов без записи используйте `Scripts\GenerateComponentProjects.cmd -Check`.

Текущая версия поддерживает явные пути файлов непосредственно в `.vcxproj`. Макросы, wildcard-пути и файлы за пределами репозитория отклоняются с ошибкой; элементы из импортируемых файлов не вычисляются.

Текстовые файлы изменяются через apply_patch и сохраняются без завершающих CR, LF и пробелов. Комментарии преимущественно на русском, сообщения коммитов на английском.