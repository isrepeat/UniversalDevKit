# SolutionInjector

Фиксированная Windows x64-дистрибуция описана в `SolutionInjector.json`: URL GitHub Release, commit репозитория, SHA-256 архива и EXE. Архив содержит готовый EXE из репозитория SolutionInjector и app-local Visual C++ Runtime DLL. Соответствие EXE исходникам не подтверждено пересборкой.

`Scripts/PowerShell/GetSolutionInjector.ps1` скачивает архив, проверяет SHA-256 и распаковывает его в игнорируемый `!tools/SolutionInjector/<версия>/`. Проверенный архив используется повторно без сети. Параметр `-LocalPath` позволяет указать тот же EXE локально; runtime DLL должны быть рядом с ним либо runtime должен быть установлен.

Пример запуска из корня UniversalDevKit:

```powershell
./Scripts/PowerShell/Connect.ps1 -ProjectPath C:/WORK/Windows/Projects/UniversalDevKit.ConsumerTest/UniversalDevKit.ConsumerTest.vcxproj -Components Helpers,Diagnostic -SolutionPath C:/WORK/Windows/Projects/UniversalDevKit.ConsumerTest/UniversalDevKit.ConsumerTest.sln
```

Для локального EXE добавьте `-SolutionInjectorPath C:/WORK/SolutionInjector/bin/SolutionInjector.exe`.

По умолчанию Connect работает с решением: при запуске CMD без аргументов спрашивает путь к `.sln`, выбирает consumer из проектов этого решения, затем действие и компоненты. Единственный consumer выбирается автоматически. Проекты самой UniversalDevKit исключены из выбора. Параметр ProjectPath позволяет явно выбрать consumer, который должен входить в указанное SolutionPath. CMD также передаёт аргументы PowerShell-скрипту.

SolutionPath вставляет всю папку MsBuild из UniversalDevKit.sln, сохраняя её иерархию: Shared, Static, Dynamic и общие настройки. Затем Connect заменяет импорт Sources.targets на прямые Shared References выбранных компонентов и их зависимостей. В `.vcxproj` появляются `Import` с `Label="Shared"`, а в `.sln` — записи `SharedMSBuildProjectFiles`, связывающие Shared-проекты с consumer. Исходники не копируются и компилируются как часть consumer.

Специальный режим без изменения solution включается только флагом ProjectOnly:

```powershell
./Scripts/PowerShell/Connect.ps1 -ProjectOnly -ProjectPath C:/WORK/Windows/Projects/UniversalDevKit.ConsumerTest/UniversalDevKit.ConsumerTest.vcxproj -Components Helpers,Diagnostic
```

Этот режим использует Sources.targets. ProjectOnly и SolutionPath нельзя комбинировать.

Повторный запуск с тем же SolutionPath обновляет Shared References и восстанавливает удалённые очисткой компоненты через повторную вставку без дубликатов. Disconnect с SolutionPath удаляет связи consumer, затем вызывает `SolutionInjector prune --apply --json` для папки UniversalDevKit. Неиспользуемые проекты и пустые папки удаляются из решения; зависимости других consumer сохраняются, исходники остаются на диске. Перед очисткой SolutionInjector создаёт резервную копию решения. Неоднозначные зависимости блокируют очистку: consumer остаётся отключённым, дерево сохраняется, причины выводятся предупреждениями. ProjectOnly не запускает очистку решения. Прежние записи Shared References с двумя GUID приводятся к стандартному формату при обновлении связей.