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

Для подключения исходников из submodule или отдельного checkout запустите двойным кликом `Scripts/Connect.cmd`. Укажите путь к `.sln`, `.vcxproj` или каталогу потребителя. Проект, действие и компонент выбираются стрелками вверх/вниз и Enter; Esc отменяет операцию до записи изменений. Доступны Helpers, Diagnostic или оба компонента. Скрипт добавляет относительный импорт `UniversalDevKit.Sources.targets`; повторное подключение обновляет тот же блок. Действие disconnect удаляет только блоки с меткой UniversalDevKit. После изменения перезагрузите проект в Visual Studio. При каждой сборке MSBuild читает импорт без повторного запуска скрипта.

Connect предлагает Helpers, Diagnostic или оба компонента. Их `.cpp` компилируются непосредственно в проекте потребителя, PCH потребителя для этих файлов отключён, объектные файлы имеют отдельные пути внутри `$(IntDir)UniversalDevKit/`. Для нескольких проектов повторите подключение с выбором каждого потребителя. Изменённый `.vcxproj` сохраняется в Git потребителя.

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

Shared-проекты задают `UniversalDevKitFilterRoots` со списком корней относительно репозитория. Текущее значение `Includes\UniversalDevKit;Sources` объединяет заголовки и реализации под фильтрами Helpers или Diagnostic. Подкаталоги внутри компонента сохраняются. Можно изменить корни и запустить UpdateProjectFilters без перемещения исходников.

`Scripts/PowerShell/UpdateProjectFilters.ps1` автоматически формирует `.vcxproj.filters` для всех проектов вне каталогов артефактов. Фильтры повторяют пути файлов относительно корня репозитория; список файлов берётся из `.vcxproj`. Добавление файла в проект остаётся отдельным действием. PowerShell-скрипты хранятся в `Scripts/PowerShell/`, CMD-обёртки — в `Scripts/`.

Запустите двойным кликом `Scripts\UpdateProjectFilters.cmd`: он автоматически создаёт или обновляет `.vcxproj.filters` всех проектов, выводит статус и ожидает нажатия клавиши. Изменения отображаются в Git. Аргументы не требуются; запуск работает независимо от текущего каталога. Неизменившиеся файлы не перезаписываются. Файлы `.filters` хранятся в Git и доступны до первой сборки; после обновления может потребоваться перезагрузить проект в Visual Studio.

Текущая версия поддерживает явные пути файлов непосредственно в `.vcxproj`. Макросы, wildcard-пути и файлы за пределами репозитория отклоняются с ошибкой; элементы из импортируемых файлов не вычисляются.

Текстовые файлы изменяются через apply_patch и сохраняются без завершающих CR, LF и пробелов. Комментарии преимущественно на русском, сообщения коммитов на английском.