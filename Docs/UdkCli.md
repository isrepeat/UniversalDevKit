# UDK CLI

Нативный CLI написан на C++20. Main.cpp разбирает команды, PowerShellScript.cpp запускает инструменты из поставки. Исходники находятся в `Sources/Windows/UdkCli`.

Компонент описан в `Projects/Components/UdkCli.json` и подключён через `msbuildApplications` в корневом `Components.json`. ProjectTools добавляет приложение и Shared-проект в папку `Projects → MsBuild → UdkCli`. Проект `UdkCli.vcxproj` импортирует Shared `.vcxitems` с исходниками. Правила `filters.roots` и `filters.files` задают папки в Visual Studio. После добавления `.cpp` или `.h` достаточно заново запустить генерацию по корневому манифесту. Параметры сборки и копирование инструментов задаются в `UdkCli.props` и `UdkCli.targets`.

| Команда | Существующий инструмент |
|---|---|
| `udk project generate [manifest]` | ProjectTools/Generate.ps1 |
| `udk project check [manifest]` | ProjectTools/Generate.ps1 с параметром -Check |
| `udk package build <package-path>` | PackageTools/Build.ps1 |
| `udk package plan <package-path>` | PackageTools/Build.ps1 с параметром -Plan |

Команды запускаются из корня потребляющего репозитория. По умолчанию команды проектов используют Components.json из текущего каталога. CLI запускает pwsh.exe и передаёт код завершения скрипта вызывающей стороне.

Проект MSBuild собирает udk.exe со статическим CRT и копирует ProjectTools и PackageTools вместе с шаблонами в каталог Tools рядом с EXE. Сборка Windows x64 из Developer PowerShell для Visual Studio:

```powershell
msbuild Projects/MsBuild/UdkCli/UdkCli.vcxproj /p:Configuration=Release /p:Platform=x64
```

Исходники ProjectTools и PackageTools находятся в `Sources/Windows/UdkCli/Tools`. При сборке каталог `Tools` копируется рядом с `udk.exe` с сохранением структуры. Для запуска нужен PowerShell 7. Требования к сборке конкретного пакета определяются PackageTools.

Для выпуска запустите `Scripts/Tools/Publish.UdkCli.cmd`. Версия берётся из обязательного для публикации поля `githubVersion` в `Projects/Components/UdkCli.json`. Для отдельного запуска версию можно задать явно через `-Version 0.1.0`. Скрипт собирает Release x64, создаёт ZIP в `!artifacts/releases/UdkCli` и показывает путь, SHA-256 и тег `udk-cli-v<версия>`. После ответа `y` скрипт публикует архив через авторизованный GitHub CLI. При отказе ZIP остаётся на диске.

Установка udk.exe в профиль пользователя, настройка PATH, закрепление версии CLI в репозитории и синхронизация CMD-файлов относятся к следующему этапу. Каркас сохраняет текущие точки входа ProjectTools и PackageTools. В комплект включается существующий архив SolutionInjector из ProjectTools, поэтому перед выпуском CLI его нужно обновить до сборки, которая использует SolutionInjectorProjectOwnership.