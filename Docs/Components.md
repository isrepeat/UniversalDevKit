# Генерация проектов компонентов

**Навигация:** [Главная](../README.md) → [Документация](README.md) → Реестр компонентов

## Содержание

- [Зависимости при подключении исходников](#зависимости-при-подключении-исходников)
- [Виртуальные папки Visual Studio](#виртуальные-папки-visual-studio)
- [Политика состояния](#политика-состояния)
- [Платформенные файлы](#платформенные-файлы)
- [CMake без дублирования списков](#cmake-без-дублирования-списков)
- [Настройки компиляции](#настройки-компиляции)
- [Исполняемые проекты MSBuild](#исполняемые-проекты-msbuild)
- [Ссылки на JSON](#ссылки-на-json)

## Ссылки на JSON

В `Package.xml` поле `version` обязательно. В описании компонента поле `githubVersion` требуется для публикации релиза на GitHub. Для локальной генерации его можно пропустить. Оба поля принимают номер версии или ссылку на поле другого JSON. Псевдонимы файлов задаются в `JsonReferences.json` в корне обрабатываемого репозитория. Пути в карте отсчитываются от этого корня.

```json
{
  "UDK_VERSION": "Version.json"
}
```

```json
{
  "version": "${UDK_VERSION.version}",
  "abiVersion": "${UDK_VERSION.abiVersion}"
}
```

Ссылка занимает всё значение поля. Резолвер поддерживает вложенные поля и сохраняет тип значения. `version` и `githubVersion` разрешаются в строки с номерами выпуска, а необязательное `abiVersion` — в целое неотрицательное число. Бинарные метаданные библиотек UDK по-прежнему задаются общим `Version.json`.

## Исполняемые проекты MSBuild

ProjectTools выбирает приложения по `kind: application` в записях массива `projects`. Для C++-приложения он создаёт Shared `.vcxitems` с исходниками и консольный `.vcxproj`, который импортирует Shared. Оба проекта добавляются в папку компонента внутри группы `Application`. `msbuildGuid` сохраняет GUID приложения, а `msbuild.properties.TargetName` задаёт имя выходного файла.

Списки `headers` и `sources` принимают шаблоны путей. Настройки MSBuild подключаются через `buildExtensions.msbuildProps` и `buildExtensions.msbuildTargets`. Пример — [UdkCli.json](../Projects/Components/Application/UdkCli.xml).

Для WPF-приложения укажите `kind: application`, `projectType: wpf` и Windows-фреймворк в `msbuild.properties.TargetFramework`. ProjectTools генерирует SDK-style `.csproj` в `Projects\MsBuild\Application\{name}` для профиля UDK. Шаблон задаёт `UseWPF`, `OutputType` и `Nullable`. В WPF и VSIX состав исходников задаётся в `sources` и `excludeSources`, с теми же масками, что и у C++. Генератор записывает C# как `Compile`, XAML в WPF как `Page`, а `App.xaml` как `ApplicationDefinition`. Примеры — [UdkCli.Setup.json](../Projects/Components/Application/UdkCli.Setup.xml) и [UdkCli.VSIX.json](../Projects/Components/Application/UdkCli.VSIX.xml).

В профиле UDK `.props` и `.targets` из `buildExtensions` относятся ко всему компоненту. ProjectTools показывает их вместе со сгенерированным `Dependencies.props` библиотеки в фильтре `Shared → Build`. Импорты MSBuild задаются отдельно от элементов дерева Visual Studio.

## Настройки компиляции

Публичный include-корень определяется по заголовкам `Includes/.../UniversalDevKit/...` из описания компонента. Для внешнего компонента с заголовком `<компонент>/Export.h` корнем служит родитель каталога компонента. CMake, генератор MSBuild, Connect и генерация Export.h используют тот же корень. При установке внешнего компонента копируются только его публичные заголовки. AndroidAppPreviewerPluginSdk теперь принадлежит отдельному репозиторию AndroidAppPreviewer и в реестр компонентов UDK не входит.

Собственные и сторонние файлы перечисляются в общих `sources` и `headers`. Все пути отсчитываются от корня репозитория через `/`, без wildcard, макросов и выхода через `..`. Каталог `ThirdParty/` обозначает происхождение кода, отдельного поля `thirdParty` больше нет. Размещение в IDE по-прежнему задаётся через `filters`; заголовки за пределами публичного include-корня компонента не становятся публичными заголовками установки.

Необязательный объект `compile` задаёт приватные настройки всех исходников компонента:

```json
"compile": {
  "includeDirectories": ["ThirdParty/spdlog/include"],
  "preprocessorDefinitions": ["SPDLOG_COMPILED_LIB", "SPDLOG_WCHAR_FILENAMES"],
  "precompiledHeader": "notUsing"
}
```

Include-каталоги должны существовать. Определения имеют вид `NAME` или `NAME=value`; они чувствительны к регистру. Include-пути и определения добавляются к настройкам сборки. `precompiledHeader` принимает `notUsing` (отключить PCH) или `inherit` (наследовать настройки сборки). По умолчанию используется `inherit`; для отключения PCH нужно явно задать `notUsing` в настройках компонента или файла. CMake использует обычные PRIVATE include-каталоги; SYSTEM не выводится из расположения файла.

Для отдельных исходников используется необязательный массив `sourceSettings`:

```json
"sourceSettings": [
  {
    "files": ["ThirdParty/Example/Source.cpp"],
    "compile": {
      "preprocessorDefinitions": ["EXAMPLE_FEATURE=1"],
      "precompiledHeader": "notUsing"
    }
  }
]
```

Каждый элемент содержит непустой список `files` и объект `compile` с теми же полями. Файл должен уже присутствовать в `sources` или `platformSources` компонента; повторная настройка одного файла запрещена. Include-пути и определения добавляются к общим, настройка PCH переопределяется. Отсутствующие поля наследуются. Для header-only компонентов `compile` и `sourceSettings` запрещены.

В MSBuild файлы сначала объявляются с меткой компонента, затем общие настройки применяются одним `ClCompile Update` к выборке по этой метке; файловые настройки идут отдельными блоками `Update`. Эти блоки изменяют метаданные только выбранных файлов; в CMake — в PRIVATE-настройки target и свойства исходников. Они не передаются другим файлам потребителя и потребителям публичных заголовков. Пути объектных файлов определяются стандартными настройками проекта Visual Studio; генератор не задаёт `ObjectFileName`. В `buildExtensions` остаются дополнительные настройки, не выраженные общей схемой. Полный пример — `Projects/Components/Library/Diagnostic.json`.

Корневой `Components.xml` схемы 6 содержит список `<Components>`. Пути отсчитываются от корневого файла. Описания библиотек находятся в `Projects/Components/Library`, а приложения — в `Projects/Components/Application`. CMake и Connect выбирают нативные библиотеки. ProjectTools обрабатывает все поддерживаемые типы проектов. Состав выпуска задаётся отдельно в `Packages/**/Package.xml`.

Описание компонента содержит `name` и массив `projects`. Запись C++-проекта содержит `kind`, `projectType`, `msbuildGuid`, `headers` и `sources`, а также необязательный массив `filters`. Для библиотеки `libraryType` по умолчанию равен `compiled`. Для библиотеки из одних заголовков укажите `headerOnly`.

После изменения реестра компонентов запустите `Scripts/GenerateComponentProjects.cmd` либо `powershell.exe -File Sources/Windows/UdkCli/Tools/ProjectTools/Generate.ps1 -ManifestPath Components.xml`. Один запуск обновляет `.vcxitems`, затем вызывает внутренний `UpdateProjectFilters.ps1` для обновления `.filters` всех проектов. Сгенерированные файлы хранятся в Git. После завершения обоих этапов перезагрузите проект или solution в Visual Studio.

Для проверки без записи: `powershell.exe -File Sources/Windows/UdkCli/Tools/ProjectTools/Generate.ps1 -ManifestPath Components.xml -Check` или `Scripts/GenerateComponentProjects.cmd -Check`. Неактуальные или отсутствующие `.vcxitems` либо `.filters` вызывают ошибку. Если устарели проекты, проверка останавливается на первом этапе; после их актуализации проверяются фильтры. Ни один этап проверки не записывает файлы.

Генератор сохраняет GUID и импорт публичных настроек. Для каждого `.cpp` по умолчанию сохраняет наследование PCH и стандартных настроек пути объектного файла.

Генерация выполняется общим [ProjectTools](ProjectTools.md) в Windows PowerShell 5.1. CMD, проверки и Connect напрямую вызывают Sources/Windows/UdkCli/Tools/ProjectTools/Generate.ps1 с путём к Components.xml. Для других репозиториев ProjectTools входит в поставку [UdkCli](UdkCli.md). XML записывается в UTF-8 без BOM и завершающих переводов строк. Повторный запуск не перезаписывает актуальные проекты. Solution обновляется через закреплённый SolutionInjector, который получает сам инструмент.

Пути заголовков и исходников задаются относительно репозитория через `/`, без MSBuild-макросов. `headers` и `sources` допускают точные пути и маски: `*` соответствует имени в одном каталоге, `**` — вложенным каталогам, `?` — одному символу. Например, `Sources/XamlRuntime/**/*.cpp` выбирает все исходники компонента. ProjectTools и CMake раскрывают маски в явные списки перед обработкой компонента. Необязательные `excludeHeaders` и `excludeSources` исключают файлы по тем же правилам; Helpers и Diagnostic исключают автоматически формируемый Export.h из списка описания. Внутренние заголовки не добавляют публичных include-путей и не включаются в HeaderCheck. Проверяются существование файлов, уникальность имён и GUID, повторяющиеся записи реестра и пути; все описания проверяются до записи.

Новый файл, подходящий под маску, не требует правки JSON: достаточно повторить генерацию ProjectTools; CMake отслеживает изменение состава через CONFIGURE_DEPENDS. Если файл находится за пределами выбранных каталогов, добавьте путь или маску в описание. Для добавления компонента создайте его JSON и внесите путь в корневой список `components`. Удаление записи не удаляет ранее сгенерированные файлы проектов автоматически.

Connect получает доступные компоненты из сгенерированного реестра компонентов Sources.targets. При добавлении компонента генератор создаёт его Shared-проект и импорт, а меню Connect обновляется автоматически. Отсутствующие Static/Dynamic-проекты создаются по шаблону Templates/Component.vcxproj.in для Windows x64 Debug/Release. Записи отсутствующих проектов добавляются в собственный solution автоматически на верхнем уровне. CMake создаёт обычные компонентные targets прямо из JSON; отдельный CMake-файл нужен только для специальных настроек.

Static/Dynamic-проекты полностью управляются ProjectTools и обновляются по общему шаблону с сохранением существующих GUID. Пользовательские настройки нужно размещать в buildExtensions, а не редактировать генерируемый проект. Пропавшие импорты восстанавливаются генерацией.

GUID новых библиотечных проектов детерминированно вычисляются из msbuildGuid Shared-проекта и варианта Static/Dynamic через SHA-256. GUID существующих проектов сохраняются; проверяется уникальность GUID всех вариантов и компонентов. GUID зависимостей определяются до формирования Dependencies.props, поэтому одновременно можно добавить несколько новых связанных компонентов.

Shared.vcxitems, Sources.targets, Dependencies.props и Static/Dynamic vcxproj полностью управляются генератором. Изменение шаблона обновляет существующие библиотечные проекты. SolutionInjector sync отслеживает принадлежащие ProjectTools записи внутри solution, пересчитывает конфигурации и Shared-ссылки и удаляет больше не нужные управляемые записи. Сами файлы проектов не удаляются. Внешние ссылки на удаляемый проект и конфликты идентичности блокируют синхронизацию. После смены msbuildGuid требуется явная миграция идентичности и внешних ссылок.

## Зависимости при подключении исходников

Необязательный массив dependencies описывает связи компонентов:

```json
"dependencies": [
  {
    "component": "Diagnostic",
    "visibility": "private",
    "linkage": "same"
  }
]
```

component должен точно совпадать с name существующего компонента. visibility принимает private/public, linkage — same/static/dynamic. В Shared зависимости same/static подключаются исходниками; dynamic сохраняет библиотечную зависимость с import-макросами и runtime-набором. Для бинарных проектов формируется Dependencies.props: same наследует вариант библиотеки, static выбирает Static, dynamic выбирает Dynamic. CMake читает эти же свойства из JSON.

GenerateComponentProjects проверяет неизвестные компоненты, повторяющиеся зависимости и циклы, затем формирует UniversalDevKit.Sources.targets. Каждый Shared-проект импортируется один раз, даже если он нужен нескольким выбранным компонентам. В ProjectOnly сохраняется выбор UniversalDevKitComponents; Sources.targets раскрывает смешанный граф при каждой сборке. После изменения графа запустите генератор. В режиме ProjectOnly зависимости раскрываются при сборке; для обычного подключения через solution повторите Connect.

Connect перед записью проверяет актуальность сгенерированных файлов. Если проверка не проходит, сначала запустите GenerateComponentProjects.cmd. XamlRuntime использует Diagnostic с visibility=private и linkage=dynamic. Для обычных Shared References и бинарного подключения после изменения JSON повторите Connect; ProjectOnly раскрывает Shared-зависимости при сборке.

## Виртуальные папки Visual Studio

Поле `filters` задаётся массивом правил.

```json
"filters": [
  { "path": "Sources/Helpers/**/*.cpp", "filter": "Implementation", "preserveTree": true },
  { "path": "Sources/Helpers/Math.cpp", "filter": "Algorithms" },
  { "path": "Sources/Helpers/**/Main.cpp", "filter": "" }
]
```

`path` задаётся от корня репозитория через `/` и поддерживает те же `*`, `?` и `**`, что `sources` и `headers`. Точный путь к каталогу равнозначен шаблону `каталог/**/*`. Правила применяются к уже выбранным файлам, включая заголовки, исходники платформ и MSBuild-расширения. Если файл совпадает с несколькими правилами, применяется последнее.

По умолчанию `filter` задаёт конечную виртуальную папку. Пустая строка помещает файл в корень проекта. При `preserveTree: true` сохраняются подпапки относительно указанного каталога или части шаблона до первого сегмента с подстановочным знаком. Например, первое правило помещает `Sources/Helpers/Text/Utf8.cpp` в `Implementation/Text`.

Исходники без совпавшего правила отображаются в корне проекта, а `.props` и `.targets` из `buildExtensions` — в папке `Build`. Генератор переносит правила в `.filters` для C++ и в метаданные `Link` для C#. Для XAML и связанного `.xaml.cs` используйте одну виртуальную папку. После изменения правил перегенерируйте проекты через `GenerateComponentProjects`.

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