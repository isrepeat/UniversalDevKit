# UDK CLI

Нативный CLI написан на C++20. Main.cpp разбирает команды, PowerShellScript.cpp запускает инструменты из поставки. Исходники находятся в `Sources/Windows/UdkCli`.

Компонент `UdkCli` описан в `Projects/Components/Application/UdkCli.xml` и зарегистрирован в списке `components` корневого `Components.xml`. ProjectTools добавляет приложение и Shared-проект в папку `Projects → MsBuild → Application → UdkCli`. Проект `UdkCli.vcxproj` импортирует Shared `.vcxitems` с исходниками. Правила `filters` задают папки в Visual Studio. После добавления `.cpp` или `.h` достаточно заново запустить генерацию по корневому манифесту. Параметры сборки и копирование инструментов задаются в `UdkCli.props` и `UdkCli.targets`.

`UdkCli.Setup` описан в `Projects/Components/Application/UdkCli.Setup.xml`. ProjectTools генерирует `.csproj` из WPF-шаблона и помещает проект в одноимённую папку в `Projects → MsBuild → Application`. Правила `filters` распределяют файлы проекта по виртуальным папкам. `TargetFramework` берётся из `msbuild.properties`, а `UdkCli.Setup.targets` подключает ZIP с CLI как ресурс при публикации установщика.

| Команда | Существующий инструмент |
|---|---|
| `udk project generate [manifest]` | ProjectTools/Generate.ps1 |
| `udk project generate --clean [manifest]` | Удаляет управляемые ProjectTools записи из решения и снимает закрепление версии |
| `udk project check [manifest]` | ProjectTools/Generate.ps1 с параметром -Check |
| `udk project update [manifest]` | Закрепляет версию запущенного CLI и вызывает ProjectTools/Generate.ps1 |
| `udk package build <package-path>` | PackageTools/Build.ps1 |
| `udk package plan <package-path>` | PackageTools/Build.ps1 с параметром -Plan |
| `udk uninstall` | Открывает окно подтверждения удаления установленного UDK CLI |

Команды запускаются из корня потребляющего репозитория. По умолчанию команды проектов используют Components.xml из текущего каталога. CLI запускает Windows PowerShell 5.1 (`powershell.exe`). Код завершения скрипта передаётся вызывающей стороне.

## Версия CLI в репозитории

Первый вызов `udk project generate` создаёт `.udk-version` рядом с манифестом **до запуска генерации**. Файл содержит версию запущенного CLI и остаётся на месте при ошибке. Добавьте его в Git вместе с файлами проектов. При явном пути к манифесту команды проектов ищут файл версии рядом с этим манифестом, а команды пакетов ищут его в текущем каталоге.

При генерации `.udk-version` добавляется в папку решения `!Repository`. Флаг `--clean` удаляет управляемые записи проектов, их файлы с сопутствующими `.filters` и `.user`, а также `.udk-version`. Схемы и исходники сохраняются. Следующая генерация заново закрепляет версию и создаёт проекты.

Если версия в файле отличается от версии запущенного CLI, UDK скачивает ZIP закреплённого релиза с GitHub, сверяет SHA-256 и распаковывает `udk.exe` вместе с `Tools` в `%LOCALAPPDATA%\UdkCli\versions\<версия>`. Следующие запуски берут поставку из кеша. Скачивание поддерживается для релизов, публикующих файл `.zip.sha256` и поддерживающих выбор версии. Без `.udk-version` команды проверки и сборки используют запущенный CLI без создания файла.

Чтобы обновить репозиторий, обновите установленный UDK, затем выполните `udk project update` из корня. Команда сразу записывает версию запущенного CLI в `.udk-version` и запускает генерацию этой версией. При ошибке новая версия остаётся записанной. Для репозитория, где используются только команды пакетов, версию можно закрепить или изменить вручную. На CI установите CLI с поддержкой выбора версии и запускайте те же команды из корня репозитория.

Проект MSBuild собирает udk.exe со статическим CRT и копирует ProjectTools и PackageTools вместе с шаблонами в каталог Tools рядом с EXE. Сборка Windows x64 из Developer PowerShell для Visual Studio:

```powershell
msbuild Projects/MsBuild/Application/UdkCli/UdkCli.vcxproj /p:Configuration=Release /p:Platform=x64
```

Исходники ProjectTools и PackageTools находятся в `Sources/Windows/UdkCli/Tools`. При сборке каталог `Tools` копируется рядом с `udk.exe` с сохранением структуры. Для запуска подходит Windows PowerShell 5.1. Требования к сборке конкретного пакета определяются PackageTools.

При первой установке можно выбрать пустую папку через **Browse**. По умолчанию используется `%LOCALAPPDATA%\Programs\UdkCli`. При обновлении установщик использует сохранённый `InstallLocation` текущего пользователя. Папка установки автоматически добавляется в пользовательский `PATH`. После установки откройте новый терминал и запустите `udk --help`.

Для удаления выполните `udk uninstall`, найдите «Uninstall UDK CLI» через «Пуск» или воспользуйтесь настройками приложений Windows. Флажок **«Удалить также кеш версий UDK»** удаляет `%LOCALAPPDATA%\UdkCli\versions` и по умолчанию выключен. Файлы `.udk-version` и каталоги `!tools` остаются в репозиториях.

## Команда в Visual Studio 2026

Установщик UDK включает VSIX для Visual Studio 2026 x64 и устанавливает его для текущего пользователя в совместимые экземпляры IDE. При обновлении UDK установщик передаёт новый VSIX штатному `VSIXInstaller.exe`. ID расширения остаётся постоянным. Версия расширения задаётся полем `version` в `UdkCli.VSIX.json`. После её изменения обновите проекты через ProjectTools. Установщик пропускает экземпляры IDE, в которых уже установлена эта версия расширения. Если установить расширение не удалось, UDK Setup откроет отдельное окно. Если Visual Studio открыта, закройте её и нажмите **Install extension**. Чтобы завершить установку CLI без расширения, нажмите **Skip** или закройте окно.

Откройте решение и выберите **Tools → Regenerate UDK Solution**. Расширение ищет `Components.xml` от каталога решения вверх до корня Git. В репозитории UDK оно вызывает локальный `ProjectTools/Generate.ps1`, в остальных случаях запускает `udk project generate`. Результат доступен в панели **Output → UDK CLI**.

Для выпуска запустите `Scripts/Tools/Publish.UdkCli.cmd` с установленным .NET 10 SDK. Версия берётся из поля `githubVersion` в `Projects/Components/Application/UdkCli.xml`. Для отдельного запуска версию можно задать явно через `-Version 0.1.4`. Скрипт собирает Release x64, создаёт ZIP, файл SHA-256 для ZIP и автономный WPF-установщик в `!artifacts/releases/UdkCli`. После ответа `y` скрипт публикует эти файлы через авторизованный GitHub CLI. При отказе файлы остаются на диске.

Повторные выпуски переиспользуют промежуточные файлы Release x64 из `!artifacts/projects/Windows-x64/UdkCli.Release`. ZIP и установщик каждого запуска сохраняются в отдельной папке под `!artifacts/releases/UdkCli`.

В комплект включается SolutionInjector `v1.1.0-dev.3` для синхронизации проектов через `SolutionInjectorProjectOwnership`.