# ProjectTools

ProjectTools находится в `Sources/Windows/UdkCli/Tools/ProjectTools` и входит в поставку [UdkCli](UdkCli.md). Из корня стороннего репозитория запускайте `udk project generate [manifest]` или `udk project check [manifest]`. Для расширенных параметров доступен `Tools/ProjectTools/Generate.ps1` из поставки.

Генерация UDK:

```powershell
pwsh -File Sources/Windows/UdkCli/Tools/ProjectTools/Generate.ps1 -ManifestPath Components.json
pwsh -File Sources/Windows/UdkCli/Tools/ProjectTools/Generate.ps1 -ManifestPath Components.json -Check
```

CMD, проверки и Connect вызывают Sources/Windows/UdkCli/Tools/ProjectTools/Generate.ps1 напрямую с параметром -ManifestPath. Обёртка Scripts/PowerShell больше не используется. Логика Connect и его контракт не изменены.

Shared и метаданные UDK формирует профиль UDK; библиотечные проекты и обновление solution выполняются общей точкой входа. Static/Dynamic теперь полностью генерируются. Существующие GUID сохраняются. Пользовательские настройки выносятся в buildExtensions. Изменение шаблона обновляет существующие проекты при следующем запуске.

Проверка генератора описана в `Tests/Infrastructure/TestProjectTools.ps1`.

ProjectTools поставляет проверяемый архив SolutionInjector v1.1.0-dev.3 и использует sync вместо вставки проектов. Владение хранится в GlobalSection(SolutionInjectorProjectOwnership) самого решения. Обновление конфигураций и Shared-ссылок, перемещение и удаление управляемых записей проверяются на временной копии до записи основного solution. Версия для Connect закреплена в `Sources/Windows/UdkCli/SolutionInjector.Connect.json`. Для тестовых реестров используются отдельные минимальные solutions, чтобы они не наследовали владение рабочими компонентами UDK.

## Контракт

Параметры: -Check проверяет результат без изменения проектов и решения; -PassThru возвращает план изменений; -SolutionInjectorPath позволяет использовать локальную копию закреплённого EXE с проверкой SHA-256. SolutionInjector v1.1.0-dev.3 поставляется архивом внутри ProjectTools, проверяется по SHA-256 архива и EXE и распаковывается в LOCALAPPDATA/UniversalDevKit/ProjectTools/SolutionInjector. Это локальная dev-сборка SolutionInjector из коммита `13f7e41`. Проверка может заполнять кэш и создаёт временные решения рядом с проверяемым solution; временные файлы удаляются.

Схема 4 использует единый список `components`. `kind` задаёт роль компонента, а пара `language` и `projectType` выбирает генератор. Поддерживаются `cpp` / `native` для библиотек и приложений, а также `csharp` / `wpf` и `csharp` / `vsix` для приложений. Для WPF ProjectTools генерирует SDK-style `.csproj` из шаблона и сопоставляет конфигурации решения с платформой `Any CPU`. В решении компоненты группируются по роли в `Library` и `Application`. В профиле UDK схема 4 размещает проекты на диске в `Projects/MsBuild/{kind}/{name}`, где `{kind}` подставляется как `Library` или `Application`. Схема 3 с `includes` остаётся доступна существующим standalone-репозиториям.

Пути компонентов, файлов и расширений отсчитываются от каталога `Components.json`. `generation.msbuild` содержит `solution`, `projectDirectory` с `{name}` и необязательным `{kind}`, `projectName` с `{name}/{variant}`, `configurations`, `platforms` и необязательные `solutionFolder`, `props`, `targets`.

Описания C++-компонентов используют `headers`, `sources`, `requirements`, `compile`, `dependencies` и `buildExtensions`. `headers` и `sources` допускают точные пути и маски `*`, `**`, `?`. `excludeHeaders` и `excludeSources` исключают файлы, а `variants` выбирает static/dynamic. Для C++-компонентов создаётся Shared, для `libraryType: headerOnly` достаточно Shared и проекта проверки заголовков в профиле UDK. `msbuildGuid` необязателен. Существующие GUID бинарных проектов сохраняются.

Генерируемые библиотечные проекты полностью управляются инструментом. Пользовательские настройки размещаются в buildExtensions.msbuildProps/msbuildTargets либо общих generation.msbuild.props/targets. msbuild.properties задаёт свойства Globals, msbuild.dynamicDefinitions — export-макросы DLL, msbuild.resolvedFiles — необязательный генерируемый JSON с явными headers/sources для существующих CMake и упаковки.

Профиль generation.profile: udk сохраняет реестр Sources.targets, export-заголовки, требования и HeaderCheck UDK. Версия схемы 2 поддерживается как совместимый вход этого профиля. Connect остаётся инструментом UDK.

В standalone-режиме platformSources, platformRequirements и sourceSettings пока отклоняются: такие настройки задаются явными расширениями MSBuild. Профиль UDK сохраняет существующую поддержку этих полей. Отбор файлов, варианты, конфигурации, импорты расширений и обновление solution доступны обоим режимам.