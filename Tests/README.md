# Проверки UniversalDevKit

## Архитектура

Fixtures/Consumers содержит приложения-потребители: MsBuild, CmakePackage, CmakeContract и RequirementsPackage. Fixtures/Libraries содержит искусственные библиотеки Diamond и Registry; их заголовки UniversalDevKit принадлежат тестовым компонентам, а не публичному API рабочего UDK.

Integration/MsBuild содержит сценарии Connect, Integration/Cmake — проверки CMake-пакета и схемы требований. Infrastructure содержит общие инструменты и проверку генератора реестра. Scripts содержит точки запуска.

RunTests.cmd запускает только сценарии Connect/MSBuild. CMake-проверки запускаются отдельно:

```powershell
./Tests/Integration/Cmake/TestCMakePackage.ps1 -CMake 'C:/Path/To/cmake.exe'
./Tests/Infrastructure/TestComponentRegistry.ps1
```

## Запуск через CMD

Обёртки и основной PS1 находятся в `Tests/Scripts/`. Для запуска двойным кликом используйте RunTests.cmd (все сценарии), RunShared.cmd, RunStatic.cmd, RunDynamic.cmd, RunModeSwitch.cmd или RunDisconnect.cmd. RunSubmodule.cmd запускает все сценарии с настоящим submodule на HEAD. Обёртки работают из любого текущего каталога, используют Windows PowerShell 5.1, ожидают нажатия клавиши после завершения и возвращают код теста.

Дополнительные параметры передаются в RunTests.ps1:

```cmd
Tests\Scripts\RunDynamic.cmd -CleanOnSuccess
Tests\Scripts\RunTests.cmd -Scenario Static -Mode Submodule -Revision HEAD
```

Пауза выполняется один раз общей обёрткой RunTests.cmd. Для автоматического запуска без паузы вызывайте RunTests.ps1 напрямую.

Запускайте через Windows PowerShell 5.1:

```powershell
powershell.exe -NoProfile -File Tests/Scripts/RunTests.ps1
powershell.exe -NoProfile -File Tests/Scripts/RunTests.ps1 -Mode Submodule -Revision HEAD
powershell.exe -NoProfile -File Tests/Scripts/RunTests.ps1 -Scenario Static
```

Нужны Git и Visual Studio с C++ tools/MSBuild. Если не задан `-SolutionInjectorPath`, Connect загружает инструмент в изолированную копию UDK; для автономного запуска можно передать путь к уже загруженному совместимому EXE. Отсутствие инструмента или ошибка проверки возвращает код 1.

`Fixtures/Consumers/MsBuild` содержит неподключённое решение с двумя приложениями. Шаблон напрямую не собирается: App1 требует подключения UDK. App2 независимо от UDK проверяет сохранность соседнего проекта. Не изменяйте шаблоны в процессе теста.

Каждый запуск создаёт отдельный Git-репозиторий Consumer под `!artifacts/tests/<run-id>/`. WorkingTree копирует tracked и untracked файлы UDK, включая текущие изменения; ignored-файлы, удалённые файлы и Tests исключаются. Submodule добавляет настоящий локальный Git submodule на выбранной ревизии; незакоммиченные изменения UDK в этот режим не попадают. Ревизия должна содержать проверяемые инструменты подключения.

Первый сценарий запускает существующие проверки графа и меню, подключает Helpers/Diagnostic Shared через настоящий Connect, повторяет Apply и проверяет неизменность настроек consumer, состава проектов и Shared-связей solution, отсутствие повторных Shared imports. Изменение форматирования или папок solution выводится отдельно как NOTE. Затем собирает всё решение в Debug/Release x64 и запускает оба приложения. MSBuild text logs и binlogs сохраняются в `logs/` окружения.

## Хранение вариантов

Diamond использует отдельный Fixtures/Libraries/Diamond: A → B/C → D и App2 → C. RunDiamond.cmd или `RunTests.ps1 -Scenario Diamond` запускает Shared, Static, Dynamic и вариант A.Dynamic → private B.Static. Для Dynamic проверяется публичная B.Dynamic и транзитивный runtime-набор. EXE запускаются с ожидаемыми DLL из чистого каталога и ограниченным PATH; конфликт A.Dynamic/C.Static должен отклоняться без изменения consumer и solution. После отключения App1 повторно собирается App2. Сценарий входит в общий запуск. Библиотечный solution fixture хранится отдельно от consumer и описывает только тестовые компоненты. Fixture предназначен для MSBuild; CMake здесь не проверяется.

Fixtures содержит готовые неподключённые `.sln/.vcxproj` и исходники. Один Consumer используется сценариями Shared, Static, Dynamic, ModeSwitch и Disconnect из Integration. Общие проверки находятся в Integration/MsBuild/Connect.Tests.ps1; способы подключения меняются только через настоящий Connect. Каждый сценарий получает отдельное окружение. По умолчанию запускаются все сценарии; параметр Scenario выбирает нужные. В PowerShell можно передать массив: `./Tests/Scripts/RunTests.ps1 -Scenario Shared,Dynamic`.

Новый способ подключения добавляется сценарием, а не копией solution. Новый тип приложения, например host с плагинами, получает отдельный шаблон Fixtures. Тестовые компоненты и JSON графа размещаются в Fixtures/Libraries и устанавливаются только во временную копию библиотеки. Итоговые подключённые решения в Git не сохраняются.

Окружение сохраняется по умолчанию и всегда при ошибке. `-CleanOnSuccess` удаляет только успешно проверенный каталог сценария. Рабочий UDK и внешние consumer не изменяются. ModeSwitch проверяет Shared → Static → Dynamic → Shared; Disconnect удаляет оба компонента и проверяет независимую сборку App2. Проверки интерактивных клавиш, обновления submodule и очистки старых DLL пока не реализованы; PASS их не подтверждает.