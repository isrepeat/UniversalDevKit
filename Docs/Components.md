# Генерация проектов компонентов

**Навигация:** [Главная](../README.md) → [Документация](README.md) → Реестр компонентов

## Содержание

- [Зависимости при подключении исходников](#зависимости-при-подключении-исходников)
- [Виртуальные папки Visual Studio](#виртуальные-папки-visual-studio)
- [Политика состояния](#политика-состояния)
- [Платформенные файлы](#платформенные-файлы)
- [CMake без дублирования списков](#cmake-без-дублирования-списков)
- [Сторонние исходники](#сторонние-исходники)

## Сторонние исходники

Необязательный массив `thirdParty` в описании компилируемого компонента содержит записи с полями `name`, `root`, `sources`, `headers`, `includeDirectories` и `compileDefinitions`. `name` уникален внутри компонента; `root` — существующий каталог под `ThirdParty/` относительно репозитория. Все остальные пути отсчитываются от `root`, перечисляются явно и не допускают wildcard или выхода через `..`. Четыре списка обязательны, но могут быть пустыми. `headers` задаёт только отображаемые в IDE заголовки, не публичные заголовки для установки.

Пример записи: `{"name":"spdlog","root":"ThirdParty/spdlog","sources":["src/spdlog.cpp"],"headers":[],"includeDirectories":["include"],"compileDefinitions":["SPDLOG_COMPILED_LIB"]}`. Полный список исходников spdlog находится в `Projects/Components/Diagnostic.json`.

Генератор MSBuild создаёт явные `ClCompile`/`ClInclude`; размещение задаётся обычными `filters.roots` и `filters.files` с путями от корня репозитория. Для spdlog корень `ThirdParty/spdlog` отображается в виртуальной папке `ThirdParty/spdlog`. Исходники зависимости не используют PCH потребителя, а объектные файлы размещаются в `$(IntDir)UniversalDevKit/<компонент>/ThirdParty/<name>/` с сохранением относительного пути.

Include-пути и определения применяются к компиляции собственных и сторонних исходников компонента: собственная реализация также может подключать заголовки зависимости. В MSBuild это метаданные отдельных файлов, в CMake — PRIVATE-настройки target. Они не передаются потребителю публичных заголовков. CMake читает тот же JSON, добавляет явно перечисленные файлы и отключает PCH для сторонних исходников. В build extensions остаются только дополнительные настройки компилятора, без списков файлов и include-путей зависимости.

Корневой `Components.json` содержит `schemaVersion` и массив `includes` с путями отдельных описаний: `Projects/Components/HeleprsTest.json`, `Projects/Components/DiagnosticTest.json`. Пути includes отсчитываются от корневого файла. Вложенные include запрещены; объединённый JSON на диске не создаётся.

Каждое описание содержит `name`, `msbuildGuid`, `headers` и `sources`, а также необязательный объект `filters`. `name` определяет компонент и имя `.vcxitems`. `msbuildGuid` сохраняет идентификатор Shared-проекта; при добавлении компонента нужен новый уникальный GUID.

После изменения реестра компонентов запустите `Scripts/GenerateComponentProjects.cmd` либо `pwsh -File Scripts/PowerShell/GenerateComponentProjects.ps1`. Один запуск обновляет `.vcxitems`, затем вызывает внутренний `UpdateProjectFilters.ps1` для обновления `.filters` всех проектов. Сгенерированные файлы хранятся в Git. После завершения обоих этапов перезагрузите проект или solution в Visual Studio.

Для проверки без записи: `pwsh -File Scripts/PowerShell/GenerateComponentProjects.ps1 -Check` или `Scripts/GenerateComponentProjects.cmd -Check`. Неактуальные или отсутствующие `.vcxitems` либо `.filters` вызывают ошибку. Если устарели проекты, проверка останавливается на первом этапе; после их актуализации проверяются фильтры. Ни один этап проверки не записывает файлы.

Генератор сохраняет GUID и импорт публичных настроек. Для каждого `.cpp` отключает PCH и создаёт объектный путь внутри `$(IntDir)UniversalDevKit/<компонент>/`, сохраняя подкаталоги. Поэтому `Sources/HeleprsTest/A/File.cpp` и `Sources/HeleprsTest/B/File.cpp` получают разные объектные файлы.

Генератор работает в PowerShell 7 и Windows PowerShell 5.1 без Codex и apply_patch. Он записывает XML напрямую, в UTF-8 без BOM и завершающих переводов строк. Повторный запуск не перезаписывает актуальные проекты.

Пути заголовков и исходников задаются относительно репозитория через `/`, без макросов и wildcard. Заголовки располагаются в `Includes/<компонент>/UniversalDevKit/<компонент>/`, исходники — в `Sources/<компонент>/`. Проверяются существование файлов, уникальность имён и GUID, повторяющиеся includes и пути, коллизии объектных файлов; все описания проверяются до записи.

Для добавления исходника измените только JSON соответствующего компонента. Для добавления компонента создайте его JSON и внесите путь в корневой includes. Удаление записи не удаляет ранее сгенерированные проекты автоматически.

Connect получает доступные компоненты из сгенерированного реестра компонентов Sources.targets. При добавлении компонента генератор создаёт его Shared-проект и импорт, а меню Connect обновляется автоматически. Отсутствующие Static/Dynamic-проекты создаются по шаблону Templates/Component.vcxproj.in для Windows x64 Debug/Release. Записи отсутствующих проектов добавляются в собственный solution автоматически на верхнем уровне. CMake создаёт обычные компонентные targets прямо из JSON; отдельный CMake-файл нужен только для специальных настроек.

Существующие Static/Dynamic-проекты не переписываются. Проверяются единственный корректный ProjectGuid и обязательные импорты Shared.vcxitems, Dependencies.props, BuildLayout.props и стандартных Microsoft.Cpp-файлов. При отсутствии импорта выдаётся ошибка до записи; исправлять существующий проект нужно явно.

GUID новых библиотечных проектов детерминированно вычисляются из msbuildGuid Shared-проекта и варианта Static/Dynamic через SHA-256. GUID существующих проектов сохраняются; проверяется уникальность GUID всех вариантов и компонентов. GUID зависимостей определяются до формирования Dependencies.props, поэтому одновременно можно добавить несколько новых связанных компонентов.

Shared.vcxitems, Sources.targets и Dependencies.props полностью управляются генератором. Static/Dynamic vcxproj создаются только при отсутствии; повторный запуск сохраняет пользовательские настройки. Изменение шаблона не обновляет существующие проекты. Удаление проекта позволяет создать его заново; после смены msbuildGuid проверьте GUID в solution и внешних ссылках.

## Зависимости при подключении исходников

Необязательный массив dependencies описывает связи компонентов:

```json
"dependencies": [
  {
    "component": "HeleprsTest",
    "visibility": "private",
    "linkage": "same"
  }
]
```

component должен точно совпадать с name существующего компонента. visibility принимает private/public, linkage — same/static/dynamic. В Shared зависимости same/static подключаются исходниками; dynamic сохраняет библиотечную зависимость с import-макросами и runtime-набором. Для бинарных проектов формируется Dependencies.props: same наследует вариант библиотеки, static выбирает Static, dynamic выбирает Dynamic. CMake читает эти же свойства из JSON.

GenerateComponentProjects проверяет неизвестные компоненты, повторяющиеся зависимости и циклы, затем формирует UniversalDevKit.Sources.targets. Каждый Shared-проект импортируется один раз, даже если он нужен нескольким выбранным компонентам. В ProjectOnly сохраняется выбор UniversalDevKitComponents; Sources.targets раскрывает смешанный граф при каждой сборке. После изменения графа запустите генератор. В режиме ProjectOnly зависимости раскрываются при сборке; для обычного подключения через solution повторите Connect.

Connect перед записью проверяет актуальность сгенерированных файлов. Если проверка не проходит, сначала запустите GenerateComponentProjects.cmd. DiagnosticTest использует HeleprsTest с visibility=private и linkage=static. Для обычных Shared References и бинарного подключения после изменения JSON повторите Connect; ProjectOnly раскрывает Shared-зависимости при сборке.

## Виртуальные папки Visual Studio

Пример настройки в JSON компонента:

```json
"filters": {
  "roots": [
    { "path": "Includes/UniversalDevKit/HeleprsTest", "filter": "Public" },
    { "path": "Sources/HeleprsTest", "filter": "Implementation" },
    { "path": "Sources/HeleprsTest/platform/windows", "filter": "Platforms/Windows" }
  ],
  "files": {
    "Sources/HeleprsTest/Math.cpp": "Algorithms"
  }
}
```

`files` задаёт точную виртуальную папку файла и имеет приоритет над roots. Пустое значение помещает файл непосредственно в корень проекта. Файл должен присутствовать в headers, sources или platformSources компонента.

В roots выбирается самый длинный подходящий path с учётом границы каталога. Этот префикс заменяется на filter, а подкаталоги ниже него сохраняются. Например, `Sources/HeleprsTest/Text/Encoding/Utf8.cpp` отображается в `Implementation/Text/Encoding`. Пустой filter убирает указанный корень. При отсутствии подходящего правила сохраняется структура относительно корня репозитория. Пути записываются через `/`; пустые сегменты, `.` и `..` запрещены.

Генератор записывает вычисленные папки в метаданные `__UniversalDevKitFilter` каждого элемента `.vcxitems`. UpdateProjectFilters переносит их в `.filters`, создавая родительские папки и пропуская пустые. Для остальных проектов остаётся прежняя поддержка UniversalDevKitFilterRoots. Изменения влияют только на отображение, исходники не перемещаются.

После изменения filters выполните только GenerateComponentProjects. В HeleprsTest и DiagnosticTest явно заданы пустые корневые фильтры для сохранения прежнего объединённого дерева.

## Политика состояния

Необязательное stateScope принимает module/process. process допускает только Dynamic. Подробнее, включая Shared-to-Dynamic и миграцию существующих проектов, — [общее состояние](StateScope.md).

Необязательные requirements и platformRequirements задают стандарт C++, потоки и системные библиотеки. Их формат, области передачи и различия адаптеров описаны в [Requirements](Requirements.md).

## Платформенные файлы

Необязательный supportedPlatforms — непустой массив Windows/Linux/Android. Без него компонент не ограничивает ОС. Необязательный platformSources — объект с именами платформ и массивами путей .cpp; общие файлы остаются в sources. Пути задаются относительно репозитория. Один файл не должен повторяться в общих и платформенных списках.

```json
"supportedPlatforms": ["Windows", "Linux"],
"platformSources": {
  "Windows": ["Sources/Example/platform/Windows/Native.cpp"],
  "Linux": ["Sources/Example/platform/Linux/Native.cpp"]
}
```

CMake использует CMAKE_SYSTEM_NAME, MSBuild — UniversalDevKitTargetOS (по умолчанию Windows). Свойство MSBuild выбирает файлы и проверяет ограничения, но не переключает toolchain. Объявление платформы в JSON не означает, что её сборка уже проверена.

## CMake без дублирования списков

ComponentDependencies.cmake читает headers/sources/platformSources непосредственно из JSON и создаёт выбранные варианты с зависимостями. ComponentRequirements.cmake обрабатывает стандарт C++, потоки и системные библиотеки. При добавлении обычного компонента отдельный CMake-файл не создаётся: он не нужен. Необязательный Projects/Cmake/<компонент>/CMakeLists.txt выполняется через include и получает список currentComponentTargets для специальных настроек, отсутствующих в общем формате. Это файл расширения общей сборки, а не самостоятельный проект для add_subdirectory.