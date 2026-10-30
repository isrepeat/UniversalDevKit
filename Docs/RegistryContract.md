# Контракт реестра компонентов

**Навигация:** [Главная](../README.md) → [Документация](README.md) → Контракт реестра

## Пример корневого реестра

```json
{
  "schemaVersion": 2,
  "includes": [
    "Projects/Components/HeleprsTest.json",
    "Projects/Components/DiagnosticTest.json"
  ]
}
```

**Неизвестные поля отклоняются.** Пути в `includes` перечисляются явно, без wildcard.

## Значения по умолчанию

Схема 2 поднимает минимальный стандарт до C++20. Явное cxxStandard=17 и реестры схемы 1 отклоняются; при миграции обновите корневой реестр и стандарт проектов-потребителей. Версии схем Package.json и бинарных манифестов независимы и не меняются.

| Поле | Значения | По умолчанию |
|---|---|---|
| `kind` | `compiled`, `headerOnly` | `compiled` |
| `stateScope` | `module`, `process` | `module` |
| `requirements.cxxStandard` | `20`, `23` | `20` |
| `requirements.threads` | `true`, `false` | `false` |
| `dependencies` | Массив связей | Пустой список |
| `headers`, `sources` | Массивы путей | Обязательны; допустимы `[]` |

## Версия схемы и идентификаторы

Реестр — внутренний API сборки UDK. Components.json содержит schemaVersion=2 (число) и непустой массив includes с явными путями Projects/Components/*.json. Неизвестные поля отклоняются. Изменение смысла существующих полей, обязательных полей или значений по умолчанию требует новой версии схемы и согласованного обновления CMake и PowerShell; новые необязательные поля принимаются только обновлёнными readers, старые версии должны выдать ошибку.

msbuildGuid записывается в форме {xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx}. Имена компонентов уникальны без учёта регистра; допустимы латинские буквы и цифры, первая буква заглавная. GUID также уникальны без учёта регистра.

## Зависимости

Поля `visibility` и `linkage` задаются явно: `public`/`private` и `same`/`static`/`dynamic`.

```json
"dependencies": [
  {
    "component": "HeleprsTest",
    "visibility": "private",
    "linkage": "static"
  }
]
```

Подробности — [Components.md](Components.md) и [Requirements.md](Requirements.md).

## Компоненты только из заголовков

```json
{
  "name": "HeaderProbe",
  "kind": "headerOnly",
  "msbuildGuid": "{984F66E5-780A-40B6-A641-4ECFCD8E0EAF}",
  "headers": [
    "Includes/HeaderProbe/UniversalDevKit/HeaderProbe/Value.h"
  ],
  "sources": [],
  "dependencies": []
}
```

**`headerOnly` задаётся явно**, а не определяется по пустому `sources`: `compiled` может добавлять реализацию через `buildExtensions`.

Ограничения первой версии:

- `sources` пустой;
- `platformSources` и `buildExtensions` отсутствуют;
- `stateScope: "process"` запрещён;
- зависимости — только `public`/`same` на другие `headerOnly`.

Зависимость **`compiled` → `headerOnly` разрешена**. Заголовочный компонент не наследует Static/Dynamic родителя. Зависимости на бинарные сервисы потребуют отдельного расширения контракта.

### Подключение

```cmake
find_package(UniversalDevKit CONFIG REQUIRED COMPONENTS HeaderProbe)

target_link_libraries(MyApplication
    PRIVATE UniversalDevKit::HeaderProbe.Headers
)
```

```cpp
#include <UniversalDevKit/HeaderProbe/Value.h>

static_assert(universaldevkit::headerprobe::Value() == 42);
```

CMake предоставляет `UniversalDevKit::<компонент>.Headers` как `INTERFACE` target. MSBuild создаёт только `.Shared.vcxitems`; consumer получает заголовки и требования без искусственных `.cpp`, `.lib` и DLL. Connect показывает только **Shared**, явный Static/Dynamic отклоняется. Shared-проект сохраняется в solution для просмотра заголовков.

### Установка

Пакет, содержащий только INTERFACE targets, не получает метаданные бинарного выпуска и проверку CRT/toolset. Его файл версии архитектурно независим. Для пакета с хотя бы одной библиотекой сохраняются обычные проверки архитектуры и бинарной совместимости.

## Проверки

`RegistryContract.cmake` проверяет версию, неизвестные поля, базовые типы, файлы и зависимости до создания targets. Генератор проектов проверяет реестр до записи. Специализированные поля проверяются соответствующими readers.

```powershell
pwsh -NoProfile -File Tests/Infrastructure/TestRegistryContract.ps1
```

Сценарий проверяет общий набор неверных JSON fixtures, Shared MSBuild и установленный CMake-пакет с цепочкой header-only зависимостей.

**Полный Diamond через CMake** остаётся отдельной задачей. При добавлении поля или изменении значения по умолчанию добавляются одинаковые положительные и отрицательные fixtures для обоих readers.