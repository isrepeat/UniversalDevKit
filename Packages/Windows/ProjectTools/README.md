# ProjectTools

Единый инструмент генерации C++ проектов MSBuild из Components.json. Поддерживаются PowerShell 7 и Windows PowerShell 5.1; SolutionInjector требует Windows x64. Пакетная точка входа MSBuild по умолчанию использует pwsh.exe; для Windows PowerShell задайте ProjectToolsPowerShell=powershell.exe и разрешите выполнение доверенного скрипта согласно политике окружения.

Из checkout UDK:

```powershell
pwsh -File Sources/Windows/ProjectTools/Generate.ps1 -ManifestPath C:/Repository/Components.json
```

Из установленного NuGet-пакета запускается тот же tools/Generate.ps1. Пакет импортирует MSBuild targets GenerateComponentProjects и CheckComponentProjects; ProjectToolsManifest задаёт абсолютный путь к Components.json. Специальный скрипт репозитория не требуется.

Параметры: -Check проверяет результат без изменения проектов и решения; -PassThru возвращает план изменений; -SolutionInjectorPath позволяет использовать локальную копию закреплённого EXE с проверкой SHA-256. SolutionInjector v1.1.0-dev поставляется архивом внутри ProjectTools, проверяется по SHA-256 архива и EXE и распаковывается в LOCALAPPDATA/UniversalDevKit/ProjectTools/SolutionInjector. Это локальная dev-сборка изменённого проекта SolutionInjector, а не опубликованный релиз. Проверка может заполнять кэш и создаёт временные решения рядом с проверяемым solution; временные файлы удаляются.

Контракт: schemaVersion 3, includes и generation.msbuild. Пути компонентов, файлов и расширений отсчитываются от каталога Components.json. generation.msbuild содержит solution, projectDirectory с {name}, projectName с {name}/{variant}, configurations, platforms, необязательные solutionFolder, props и targets.

Компоненты сохраняют поля UDK: name, kind, headers, sources, requirements, compile, dependencies, buildExtensions. headers/sources допускают точные пути и маски *, **, ?. excludeHeaders/excludeSources исключают файлы. variants выбирает static/dynamic. Shared создаётся для всех компонентов; headerOnly не создаёт бинарные варианты. msbuildGuid необязателен; существующие GUID бинарных проектов сохраняются.

Генерируемые библиотечные проекты полностью управляются инструментом. Пользовательские настройки размещаются в buildExtensions.msbuildProps/msbuildTargets либо общих generation.msbuild.props/targets. msbuild.properties задаёт свойства Globals, msbuild.dynamicDefinitions — export-макросы DLL, msbuild.resolvedFiles — необязательный генерируемый JSON с явными headers/sources для существующих CMake и упаковки.

Профиль generation.profile: udk сохраняет реестр Sources.targets, export-заголовки, требования и HeaderCheck UDK. Версия схемы 2 поддерживается как совместимый вход этого профиля. Connect остаётся инструментом UDK.

ProjectTools использует SolutionInjector sync с владельцем ProjectTools. Контракт явно выбирает идентичности проектов для первоначального принятия под управление; далее реестр внутри solution отслеживает владельца, тип и путь. При изменении variants проекты добавляются и удаляются из solution, mappings конфигураций и Shared-ссылки пересчитываются, проекты перемещаются в соответствующие папки. Посторонние проекты и секции сохраняются; файлы проектов автоматически не удаляются. Удаление или смена пути блокируются, если посторонний потребитель использует старый проект либо анализ зависимостей неоднозначен. Connect продолжает использовать свою закреплённую версию SolutionInjector.

В standalone-режиме platformSources, platformRequirements и sourceSettings пока отклоняются: такие настройки задаются явными расширениями MSBuild. Профиль UDK сохраняет существующую поддержку этих полей. Отбор файлов, варианты, конфигурации, импорты расширений и обновление solution доступны обоим режимам.