# UDK CLI

Нативный CLI написан на C++20. Main.cpp разбирает команды, PowerShellScript.cpp запускает инструменты из поставки. Исходники находятся в `Sources/Windows/UdkCli`.

Компонент описан в `Projects/Components/UdkCli.json` и подключён через `msbuildApplications` в корневом `Components.json`. ProjectTools добавляет приложение и Shared-проект в папку `Projects → MsBuild → UdkCli`. Проект `UdkCli.vcxproj` импортирует Shared `.vcxitems` с исходниками. Правила `filters.roots` и `filters.files` задают папки в Visual Studio. После добавления `.cpp` или `.h` достаточно заново запустить генерацию по корневому манифесту. Параметры сборки и копирование инструментов задаются в `UdkCli.props` и `UdkCli.targets`.

| Команда | Существующий инструмент |
|---|---|
| `udk project generate [manifest]` | ProjectTools/Generate.ps1 |
| `udk project check [manifest]` | ProjectTools/Generate.ps1 с параметром -Check |
| `udk package build <package-path>` | PackageTools/Build.ps1 |
| `udk package plan <package-path>` | PackageTools/Build.ps1 с параметром -Plan |
| `udk uninstall` | Открывает окно подтверждения удаления установленного UDK CLI |

Команды запускаются из корня потребляющего репозитория. По умолчанию команды проектов используют Components.json из текущего каталога. CLI запускает pwsh.exe и передаёт код завершения скрипта вызывающей стороне.

Проект MSBuild собирает udk.exe со статическим CRT и копирует ProjectTools и PackageTools вместе с шаблонами в каталог Tools рядом с EXE. Сборка Windows x64 из Developer PowerShell для Visual Studio:

```powershell
msbuild Projects/MsBuild/UdkCli/UdkCli.vcxproj /p:Configuration=Release /p:Platform=x64
```

Исходники ProjectTools и PackageTools находятся в `Sources/Windows/UdkCli/Tools`. При сборке каталог `Tools` копируется рядом с `udk.exe` с сохранением структуры. Для запуска нужен PowerShell 7. Требования к сборке конкретного пакета определяются PackageTools.

При первой установке можно выбрать пустую папку через **Browse**. По умолчанию используется `%LOCALAPPDATA%\Programs\UdkCli`. При обновлении установщик использует сохранённый `InstallLocation` текущего пользователя. Добавление папки в пользовательский `PATH` включено по умолчанию. После установки откройте новый терминал и запустите `udk --help`. Для удаления выполните `udk uninstall`, найдите «Uninstall UDK CLI» через «Пуск» или воспользуйтесь настройками приложений Windows.

Для выпуска запустите `Scripts/Tools/Publish.UdkCli.cmd` с установленным .NET 10 SDK. Версия берётся из поля `githubVersion` в `Projects/Components/UdkCli.json`. Для отдельного запуска версию можно задать явно через `-Version 0.1.0`. Скрипт собирает Release x64, создаёт ZIP и автономный WPF-установщик в `!artifacts/releases/UdkCli` и показывает пути, SHA-256 и тег `udk-cli-v<версия>`. После ответа `y` скрипт публикует оба файла через авторизованный GitHub CLI. При отказе файлы остаются на диске.

Повторные выпуски переиспользуют промежуточные файлы Release x64 из `!artifacts/projects/Windows-x64/UdkCli.Release`. ZIP и установщик каждого запуска сохраняются в отдельной папке под `!artifacts/releases/UdkCli`.

В комплект включается существующий архив SolutionInjector из ProjectTools. Перед выпуском CLI его нужно обновить до сборки, которая использует SolutionInjectorProjectOwnership.