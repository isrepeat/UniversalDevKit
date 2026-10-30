# Diagnostic: первый этап проверок

Один C++20 набор из Tests/Fixtures/Consumers/Diagnostic собирает настоящий Diagnostic.Dynamic и два независимо скомпилированных потребителя DiagnosticModuleA/B. На Windows это EXE + DLL, на Android — native executable + SO. Каждый из трёх сценариев запускается отдельным процессом. Examples не используются.

## Сценарии

- contract: LoggerInitResult, занятый ID/файл, неверный размер, системная ошибка каталога, все уровни и Off, отсутствие вычисления отключённых аргументов, немедленная доступность записи до Shutdown, narrow/wide UTF-8 (кириллица, японский, emoji), embedded NUL, некорректная wide-строка, явный пользовательский std::formatter, готовый текст со скобками, контекст объекта, scope/return/исключение, append/truncate, Unicode-путь, создание каталогов, два независимых ID, маркеры сессий, ротация с одним архивом и усечение без архива, oversized-запись и ротация при повторном открытии, повторный Shutdown, повторная инициализация и захваченный резервный stderr после остановки с проверкой фильтра.
- threads: восемь одновременных Initialize одного ID (ровно один успех), затем 800 уникальных записей из восьми потоков. Проверяется точное множество строк: без потерь, дублей, лишних или перемешанных записей.
- modules: инициализация из модуля A видна главному модулю и B; повторная инициализация отвергается везде; изменение фильтра из B видно A/главному модулю; все три пишут в один файл; Shutdown главного модуля позволяет повторную инициализацию из B. Это обнаруживает отдельные backend по DLL/SO, а не только работоспособность линковки.

Время, ID потока, абсолютные пути и написание функций намеренно не сравниваются между ОС. Обязателен общий результат DIAGNOSTIC_PASS для каждого сценария. Самостоятельные Unicode-тесты и системные каталоги не дублируются: здесь проверяется их интеграция с логгером.

## Windows

```powershell
./Tests/Integration/Diagnostic/Diagnostic.Tests.ps1
```

По умолчанию Debug и Release x64, Visual Studio 2026. CMake берётся из PATH или Visual Studio; можно передать -CMake. Есть CMD-точка Tests/Scripts/RunDiagnosticTests.cmd. Общий runner включает DiagnosticContract в Windows-группу. CMake fixture также регистрирует Diagnostic.contract/threads/modules в CTest (таймаут 180 секунд).

## Android

```powershell
./Tests/Integration/Diagnostic/Diagnostic.Tests.ps1 -Platform Android -SkipDevice
./Tests/Integration/Diagnostic/Diagnostic.Tests.ps1 -Platform Android -Serial DEVICE_SERIAL
```

Поддержаны arm64-v8a (по умолчанию) и x86_64 через -Abi; NDK r27c определяется штатным Scripts/Android/ResolveToolchain.ps1. Требуются CMake и Ninja. -AndroidNdk, -AndroidSdk, -Ninja и -CMake позволяют задать пути. Gradle/JDK/APK не нужны: через adb передаются native executable, обе потребляющие SO, Diagnostic SO и libc++_shared.so из того же NDK. Набор запускается в уникальной папке /data/local/tmp с собственным LD_LIBRARY_PATH; логи возвращаются в отчёт. На Windows-host явно передаётся --driver-mode=g++: при CMake/Ninja пути в формате 8.3 могут скрыть ++ в имени clang++ и привести к пропуску C++ runtime при линковке.

Без -SkipDevice требуется ровно одно авторизованное устройство либо явный -Serial и совместимый ABI. Отсутствующее устройство не считается успешным выполнением. -SkipDevice означает только сборку: Build=Passed, Execution=DeviceNotRun. Эмулятор автоматически не устанавливается и не запускается. Общий Android runner включает DiagnosticAndroid с фактическим запуском: передайте -AndroidSerial при необходимости. Для build-only используйте прямую команду с -SkipDevice.

Это проверка Android native ABI/stdlib/файлов/потоков и общей SO, а не жизненного цикла APK или Context/getFilesDir: тест пишет в переданный writable-каталог. UWP/MSIX, debugger, цвета терминала, физическое сохранение при сбое питания и аварийные процессы относятся к следующим этапам. Детерминированные гонки ожидания Shutdown тоже пока не включены; текущий набор вызывает Shutdown после завершения пишущих потоков.

## Отчёт

Артефакты находятся в !artifacts/tests/diagnostic-<GUID>/. summary.csv отдельно фиксирует Build и Execution по конфигурации/сценарию; логи конфигурации, сборки и каждого native-запуска сохраняются. Ошибка сборки, отказ сценария, отсутствие success marker или устройства дают код завершения 1. Явный успешный build-only возвращает 0 со статусом DeviceNotRun. Вызовы инструментов ограничены таймаутом; device-логи сохраняются, созданная временная device-папка автоматически не удаляется.