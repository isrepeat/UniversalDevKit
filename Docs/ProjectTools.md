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

Контракт: schemaVersion 3, includes и generation.msbuild. Пути компонентов, файлов и расширений отсчитываются от каталога Components.json. generation.msbuild содержит solution, projectDirectory с {name}, projectName с {name}/{variant}, configurations, platforms, необязательные solutionFolder, props и targets.

Компоненты сохраняют поля UDK: name, kind, headers, sources, requirements, compile, dependencies, buildExtensions. headers/sources допускают точные пути и маски *, **, ?. excludeHeaders/excludeSources исключают файлы. variants выбирает static/dynamic. Shared создаётся для всех компонентов; headerOnly не создаёт бинарные варианты. msbuildGuid необязателен; существующие GUID бинарных проектов сохраняются.

Генерируемые библиотечные проекты полностью управляются инструментом. Пользовательские настройки размещаются в buildExtensions.msbuildProps/msbuildTargets либо общих generation.msbuild.props/targets. msbuild.properties задаёт свойства Globals, msbuild.dynamicDefinitions — export-макросы DLL, msbuild.resolvedFiles — необязательный генерируемый JSON с явными headers/sources для существующих CMake и упаковки.

Профиль generation.profile: udk сохраняет реестр Sources.targets, export-заголовки, требования и HeaderCheck UDK. Версия схемы 2 поддерживается как совместимый вход этого профиля. Connect остаётся инструментом UDK.

В standalone-режиме platformSources, platformRequirements и sourceSettings пока отклоняются: такие настройки задаются явными расширениями MSBuild. Профиль UDK сохраняет существующую поддержку этих полей. Отбор файлов, варианты, конфигурации, импорты расширений и обновление solution доступны обоим режимам.