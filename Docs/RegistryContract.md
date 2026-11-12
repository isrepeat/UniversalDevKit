# Контракт реестра компонентов

**Навигация:** [Главная](../README.md) → [Документация](README.md) → Контракт реестра

## Пример корневого реестра

```json
{
  "schemaVersion": 5,
  "components": [
    "Projects/Components/Library/Helpers.json",
    "Projects/Components/Library/Diagnostic.json",
    "Projects/Components/Application/UdkCli.json"
  ],
  "generation": { "profile": "udk" }
}
```

**Неизвестные поля отклоняются.** Пути в `components` перечисляются явно, без wildcard.

В схеме 5 описание компонента содержит `name` и непустой массив `projects`. Настройки сборки и поля из таблицы ниже относятся к записи проекта. Библиотека может содержать нативный проект `cpp/native` и управляемый проект `csharp/classLibrary`. Приложение содержит одну запись `application`. Для C# class library задайте `msbuild.properties.TargetFramework` и исходники `sources`. ProjectTools генерирует SDK-style проект под узлом компонента в solution.

`id` — необязательный идентификатор проекта, уникальный в пределах компонента. Он нужен, когда на проект ссылается `runtimeDependencies`. C# class library может указать `{ "projectId": "native", "variant": "Dynamic" }` для нативной DLL того же компонента. ProjectTools добавляет зависимость сборки в Visual Studio. Состав NuGet задаётся в `Package.json`. CMake использует запись нативной библиотеки. Пример обоих проектов — [Diagnostic.json](../Projects/Components/Library/Diagnostic.json).

## Значения по умолчанию

Минимальный стандарт C++ для библиотек — C++20. Версии схем Package.json и бинарных манифестов независимы от реестра компонентов.

| Поле | Значения | По умолчанию |
|---|---|---|
| `kind` | `library`, `application` | Обязателен в схемах 4 и 5 |
| `language` | `cpp`, `csharp` | Обязателен в схемах 4 и 5 |
| `projectType` | `native` для C++, `wpf` и `vsix` для C#-приложений, `classLibrary` для C#-библиотек в схеме 5 | Обязателен в схемах 4 и 5 |
| `libraryType` | `compiled`, `headerOnly` | `compiled` для библиотек |
| `stateScope` | `module`, `process` | `module` |
| `requirements.cxxStandard` | `20`, `23` | `20` |
| `requirements.threads` | `true`, `false` | `false` |
| `dependencies` | Массив связей | Пустой список |
| `headers`, `sources` | Массивы путей C++-компонента | Обязательны для C++; допустимы `[]` |

## Версия схемы и идентификаторы

Реестр — внутренний API сборки UDK. Схемы 4 и 5 содержат непустой массив `components`. В схеме 4 поля проекта лежат непосредственно в описании компонента. ProjectTools также принимает схемы 2 и 3 для существующих манифестов. Для профиля UDK задайте `generation.profile: udk`.

`msbuildGuid` записывается в форме `{xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx}`. Имена и GUID уникальны без учёта регистра. В именах C++-компонентов допустимы латинские буквы и цифры, первая буква заглавная. В именах существующих C#-проектов также допускаются точки.

## Зависимости

Поля `visibility` и `linkage` задаются явно: `public`/`private` и `same`/`static`/`dynamic`.

```json
"dependencies": [
  {
    "component": "Diagnostic",
    "visibility": "private",
    "linkage": "dynamic"
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