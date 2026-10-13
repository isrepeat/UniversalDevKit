# Проверки UniversalDevKit

Необязательные сборочные расширения проверяются отдельно: `pwsh -NoProfile -File Tests/Infrastructure/TestBuildExtensions.ps1`. Fixture Generated создаёт публичный заголовок и реализацию, проверяет инкрементальную генерацию CMake/MSBuild, Shared и установленный CMake-пакет. Подробности — [сборочные расширения](../Docs/BuildExtensions.md).

HeaderIsolation проверяет компонентный include-корень Helpers.Headers без сборки библиотек: Helpers и Core доступны, заголовки Diagnostic недоступны. Проверка входит в TestCMakePackage.ps1; ограниченный пакет также проверяется на отсутствие заголовков исключённого Diagnostic.

Runtime-сценарий дополнительно проверяет параллельную сборку одного solution с двумя consumer: App1 использует /MD(d), App2 — /MT(d). Библиотеки собираются с настройками каждого consumer без общего UniversalDevKitRuntime; хеши доставленных DLL сверяются с соответствующими md/mt-артефактами. Смешанная сборка выполняется первой в новом окружении.

**Навигация:** [Главная](../README.md) → Тесты

## Содержание

- [Как пользоваться тестами](#как-пользоваться-тестами)
- [Покрытие: от простых проверок к сложным](#покрытие-от-простых-проверок-к-сложным)
- [Как понимать результат и находить ошибку](#как-понимать-результат-и-находить-ошибку)
- [Устройство окружений и дополнительные параметры](#устройство-окружений-и-дополнительные-параметры)
- [Запуск через CMD](#запуск-через-cmd)
- [Хранение вариантов](#хранение-вариантов)

Для просмотра и редактирования тестов откройте `UniversalDevKit.Tests.sln` в корне репозитория. Solution повторяет дерево Tests; fixture-проекты представлены как Solution Items. Build этого решения не запускает сценарии: используйте `Tests/Scripts/RunTests.cmd` или отдельные команды ниже. Основное решение UniversalDevKit.sln содержит только ссылки на инструкцию, запуск и тестовое решение.

TestCMakePackage.ps1 дополнительно запускает LoggingStatic/LoggingDynamic в Debug/Release: контракт буфера и CR/LF, одновременные вызовы четырёх потоков, ошибки вывода с исключениями и без, восстановление после ошибки. Используется один экземпляр Diagnostic с /MD. Выгрузка плагинов и независимые /MT runtime этим сценарием не проверяются.

## Как пользоваться тестами

Сценарий Runtime запускается через `RunTests.ps1 -Scenario Runtime`: Debug/Release с /MD и /MT, Dynamic Diagnostic с внутренней Static Helpers, запуск consumer, сохранение обоих CRT-вариантов и отказ при конфликте CRT. Для /MT параметр UniversalDevKitRuntime=Static передаётся всей сборке. Этот сценарий проверяет сборку из исходников; совместимость готового пакета по CRT и нескольким toolsets он не подтверждает.

Команды ниже выполняются из корня UniversalDevKit. Нужны Git, Windows PowerShell 5.1 и Visual Studio с C++ tools/MSBuild. Открытие UniversalDevKit.Tests.sln удобно для просмотра файлов; команда Build этого решения не заменяет запуск тестов.

Начните с быстрых проверок без сборки приложений:

```powershell
powershell.exe -NoProfile -File Scripts/PowerShell/Connect.Tests.ps1
powershell.exe -NoProfile -File Tests/Infrastructure/TestComponentRegistry.ps1
```

Затем проверьте один способ подключения, например Shared или Dynamic:

```powershell
powershell.exe -NoProfile -File Tests/Scripts/RunTests.ps1 -Scenario Shared
powershell.exe -NoProfile -File Tests/Scripts/RunTests.ps1 -Scenario Dynamic
```

Для полного набора MSBuild-сценариев и проверки закоммиченной версии через submodule:

```powershell
powershell.exe -NoProfile -File Tests/Scripts/RunTests.ps1
powershell.exe -NoProfile -File Tests/Scripts/RunTests.ps1 -Mode Submodule -Revision HEAD
```

WorkingTree используется по умолчанию и проверяет текущие tracked/untracked файлы, включая незакоммиченные изменения. Submodule проверяет выбранную ревизию; локальные изменения в неё не входят. Обёртки RunTests.cmd и RunSubmodule.cmd выполняют соответствующие запуски с паузой в конце.

## Покрытие: от простых проверок к сложным

1. **Граф и меню.** Scripts/PowerShell/Connect.Tests.ps1 проверяет расчёт вариантов зависимостей, наборы линковки, import-макросов и runtime, отклонение конфликтов и отдельные проверки меню/форматирования. Полный интерактивный сеанс клавиатуры этот тест не воспроизводит. Это самостоятельный тест; Integration/MsBuild/Connect.Tests.ps1 с тем же именем содержит общие функции интеграционных сценариев. RunTests.ps1 использует оба файла по назначению.
2. **Генератор реестра.** Infrastructure/TestComponentRegistry.ps1 проверяет создание библиотечных проектов и их добавление в solution, выбор платформенных исходников, требования C++20 и системной библиотеки, ограничения process-state компонентов и отклонение некорректных требований JSON.
3. **Shared.** Подключает исходники Helpers/Diagnostic и зависимости через настоящий Connect. Повторный Apply не должен менять настройки consumer и связи solution или дублировать imports. Собирает Debug/Release x64 и запускает App1 и независимый App2; проверяет сохранность файла соседнего проекта.
4. **Static.** Повторяет интеграционную проверку со статическими библиотеками: проверяет ссылки без Shared imports, окончательную линковку и запуск обоих приложений в Debug/Release x64.
5. **Dynamic.** Проверяет бинарное подключение, сборку DLL и consumer, доставку Diagnostic DLL и запуск обоих приложений в Debug/Release x64. Транзитивный runtime-набор дополнительно проверяется сценарием Diamond.
6. **ModeSwitch.** В одном окружении последовательно переключает Shared → Static → Dynamic → Shared. Для каждого режима выполняет проверки подключения, повторного Apply, сборки и запуска.
7. **Disconnect.** После успешного Shared-подключения удаляет компоненты из App1, проверяет отсутствие блоков интеграции и независимую сборку/запуск App2 в Debug/Release. App1 после отключения не собирается: его исходники всё ещё используют API UDK.
8. **Export.** Использует отдельный тестовый компонент ExportProbe. Проверяет Static/Dynamic Debug/Release x64, вызов публичной функции внешним consumer и метаданные версии. Через dumpbin проверяет наличие публичного UdkPublicProbe и отсутствие внутреннего UdkInternalProbe в экспортах DLL.
9. **Diamond.** Проверяет ромб A → B/C → D и второй consumer App2 → C: Shared/Static/Dynamic, публичные и внутренние зависимости, вариант с private B.Static, отсутствие дублирования и точный набор DLL. Запускает EXE из чистого каталога с ограниченным PATH. Конфликт вариантов должен отклоняться без изменения .sln/.vcxproj; после Disconnect App1 повторно собирается и запускается App2.
10. **CMake-пакет.** Integration/Cmake/TestCMakePackage.ps1 запускается отдельно. Проверяет сборку, установку и перенос пакета, подключение внешнего consumer, конфликты вариантов в установленном пакете и при подключении исходников, выбор компонентов/вариантов, отказ для неизвестного или исключённого компонента, отсутствующей Debug-конфигурации и несовместимой архитектуры. Проверяет требования компонентов и fixture с динамическим сервисом через CTest до и после установки.

Для отдельной CMake-проверки укажите доступный cmake.exe; по умолчанию используется generator Visual Studio 18 2026:

```powershell
powershell.exe -NoProfile -File Tests/Integration/Cmake/TestCMakePackage.ps1 -CMake 'C:/Path/To/cmake.exe'
```

## Как понимать результат и находить ошибку

RunTests.ps1 выводит PASS для каждого успешно завершённого сценария. Полный MSBuild-набор прошёл, если все семь выбранных по умолчанию сценариев получили PASS и процесс завершился с кодом 0. FAIL и код 1 означают ошибку проверки или окружения; читайте причину после FAIL. NOTE о форматировании solution сам по себе не означает провал теста. Успех MSBuild-набора не подтверждает отдельные CMake-проверки.

Каждый MSBuild-сценарий получает собственный Git-репозиторий consumer и копию UDK под !artifacts/tests/<run-id>/. Рабочий UDK и внешние consumer не изменяются. Каталог сохраняется по умолчанию, а при ошибке его путь выводится как Preserved workspace. В logs/ находятся текстовые логи MSBuild и .binlog; они позволяют увидеть команду сборки и причину ошибки. Параметр -CleanOnSuccess удаляет только успешно проверенные окружения.

Ожидаемые отказы, например конфликт вариантов в Diamond или несовместимая архитектура CMake-пакета, являются частью проверки. Сам сценарий проходит только если отказ произошёл ожидаемым способом.

Текущие Windows-проверки не подтверждают Linux/Android, потребление NuGet/AAR, полный интерактивный Connect, обновление существующего submodule, очистку устаревших DLL, Check/Repair ручных изменений и восстановление файлов при частичном сбое.

## Устройство окружений и дополнительные параметры

RunExport.cmd проверяет общий API-макрос: Static/Dynamic Debug/Release Windows x64, вызов публичной функции отдельным consumer и таблицу экспортов DLL через dumpbin. Сценарий Export включён в общий запуск; Linux/Android в этой проверке не используются. Политика версий и ABI описана в Docs/Abi.md в корне репозитория.

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