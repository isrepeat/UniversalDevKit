# UniversalDevKit

Общие C++-хелперы для Windows, Linux и Android. Минимальная версия языка — C++17.

## Структура

- `include/UniversalDevKit/` — единственный экземпляр публичных заголовков и шаблонной реализации.
- `cmake/` — интеграция установленного CMake-пакета.
- `msbuild/` — проект для Visual Studio и публичные настройки подключения.
- `UniversalDevKit.sln` — solution с конфигурациями Debug и Release для x64.

Пока библиотека содержит только заголовки: проект MSBuild имеет тип Utility, а CMake предоставляет INTERFACE target. Они не создают бинарную библиотеку.

## Подключение через CMake

```cmake
add_subdirectory(external/UniversalDevKit)
target_link_libraries(MyApplication PRIVATE UniversalDevKit::Headers)
```

Также поддерживаются `cmake --install` и подключение установленного пакета через `find_package(UniversalDevKit CONFIG REQUIRED)`.

## Подключение через MSBuild

Импортируйте после `Microsoft.Cpp.props` в C++-проекте потребителя:

```xml
<Import Project="..\external\UniversalDevKit\msbuild\UniversalDevKit.props" />
```

Потребитель выбирает C++17 или более новый стандарт самостоятельно. Импорт добавляет путь к заголовкам и сохраняет существующие include-пути. Открытие solution не заменяет этот импорт в другом проекте.

## Использование

```cpp
#include <UniversalDevKit/Math.h>

namespace udk = universaldevkit;
static_assert(udk::math::Square(5) == 25);
```

`Square` использует обычное умножение типа аргумента и не проверяет переполнение.

## Расширение

Публичный namespace — `universaldevkit`. Новые заголовки добавляются в `include/UniversalDevKit/`, компилируемая реализация — в `src/`. CMake и MSBuild используют одни исходники. Платформенные реализации выбираются явно для каждой поддерживаемой платформы. Описание упаковки NuGet и Android добавляется в `packaging/`, готовые пакеты не хранятся в Git.

## Правила изменений

Текстовые файлы изменяются через apply_patch и сохраняются без завершающих CR, LF и пробелов. Комментарии преимущественно на русском, сообщения коммитов на английском.