# Diagnostic

Минимальный C++20 сервис логирования со статическим классом `Logger`: `UniversalDevKit::Diagnostic.Dynamic`, namespace `universaldevkit::diagnostic`. Компонент имеет `stateScope=process`: штатные способы подключения разрешают только DLL/SO. Все модули приложения должны использовать один загруженный экземпляр Diagnostic. Тестовый DiagnosticTest остаётся отдельным компонентом.

## Результат инициализации

Initialize возвращает LoggerInitResult с полями error (LoggerInitError), systemError (std::error_code), message (текст причины). Успех: error == None, остальные поля пусты. explicit operator bool позволяет использовать if (!result) и прежнюю проверку if (!Logger::Initialize(...)). Неявное присваивание результата переменной bool больше не поддерживается; ABI изменён, потребителей DLL необходимо пересобрать.

```cpp
const auto result = diagnostic::Logger::Initialize(loggerOptions);
if (!result) {
    // result.error — причина для программной обработки.
    // result.message — описание; systemError заполнен, если исходная ошибка предоставила код.
}
```

Коды: AlreadyInitialized, FileAlreadyUsed, InvalidOptions, DirectoryUnavailable, FileOpenFailed, PackageUnavailable, UnsupportedPlatform, ShutdownRegistrationFailed, InitializationFailed, ShutdownInProgress. InvalidOptions проверяется до открытия/усечения файла, включая уровни и лимиты ротации. Уже активный ID сохраняет конфигурацию при отказе. Неуспешно создаваемый ID не публикуется. Ошибки spdlog содержат текст, но systemError может быть пустым: backend не предоставляет структурированный исходный код. Глобальной последней ошибки нет.

Initialize больше не noexcept: результат содержит динамическую строку, поэтому std::bad_alloc может выйти вызывающему коду, в том числе при формировании сообщения ошибки. Обычные ошибки конфигурации и файловой системы возвращаются результатом; Write/Flush/Shutdown остаются noexcept.

## Использование

При первой успешной Initialize сервис один раз регистрирует Logger::Shutdown через std::atexit. При штатном завершении приложения ручной Shutdown не требуется. Явный вызов остаётся доступным для раннего освобождения ресурсов; повторная инициализация не добавляет новые обработчики завершения. При abort, TerminateProcess, необработанном access violation или другом аварийном завершении автоматический Shutdown не гарантируется. Рабочие потоки должны завершиться до выхода из main; Diagnostic DLL должна оставаться загруженной, пока есть её пользователи. Поздние записи после автоматического Shutdown используют fallback.

```cpp
#include <UniversalDevKit/Diagnostic/Logging.h>

namespace diagnostic = universaldevkit::diagnostic;

int main() {
    if (!diagnostic::Logger::Initialize({ diagnostic::Level::Debug })) {
        return 1;
    }
    UDK_LOG_INFO("Application", "Started version {}", 1);
    diagnostic::Logger::SetLevel(diagnostic::Level::Warning);
    UDK_LOG_DEBUG("Application", "Filtered message {}", 42);
}
```

Каждый LoggerId имеет собственный минимальный уровень и синхронные выходы: файл/stderr, опционально консоль и debugger. Пустой filePath сохраняет stderr; непустой включает файловую запись. У записи есть уровень, категория, UTF-8 сообщение и source_location. Категория остаётся текстовой меткой, маршрутизации по категориям нет. Уровни: Trace, Debug, Info, Warning, Error, Critical, Off.

## Файлы и ID

```cpp
diagnostic::LoggerOptions loggerOptions;
loggerOptions.minimumLevel = diagnostic::Level::Debug;
loggerOptions.filePath = L"Logs/application.log";
loggerOptions.logFolder = diagnostic::LogFolder::ApplicationOrPackage;
loggerOptions.fileMode = diagnostic::FileMode::Append;
loggerOptions.maxFileSize = 10 * 1024 * 1024;
loggerOptions.maxFiles = 1;
loggerOptions.appendNewSession = true;

if (!diagnostic::Logger::Initialize(loggerOptions)) {
    return 1;
}
UDK_LOG_INFO("Application", "Started version {}", 1);

loggerOptions.filePath = L"Logs/network.log";
if (!diagnostic::Logger::Initialize(loggerOptions, 7)) {
    return 2;
}
UDK_LOG_WARNING_N(7, "Network", "Retry attempt {}", 3);
diagnostic::Logger::SetLevel(diagnostic::Level::Error, 7);
```

ID 0 используется всеми прежними макросами и методами по умолчанию. Макросы UDK_LOG_TRACE_N/DEBUG_N/INFO_N/WARNING_N/ERROR_N/CRITICAL_N принимают первым аргументом ID. Для готового текста: Logger::Write(level, category, message, sourceLocation, loggerId). Для форматирования напрямую — Logger::LogForId(loggerId, level, category, sourceLocation, format, args...). Flush(loggerId) сбрасывает выбранный логгер; Shutdown завершает все ID. Повторная Initialize того же активного ID и открытие уже занятого другим ID файла возвращают неуспешный LoggerInitResult.

FileMode::Append сохраняет существующее содержимое, FileMode::Truncate очищает активный файл при инициализации. Родительские папки создаются автоматически. Для Windows используются wide filename API spdlog, поэтому Unicode в пути не зависит от ANSI code page.

maxFileSize — предел активного файла, положительное число байт. При превышении выполняется штатная ротация spdlog: maxFiles задаёт число архивов (по умолчанию один, application.1.log). maxFiles = 0 отключает архивы: при переполнении активный файл усекается. Это не прежнее удаление первой половины файла: сохранение предыдущих данных обеспечивают архивы. Уже превышающий лимит файл обрабатывается при открытии. Одна строка, размер которой превышает лимит, записывается целиком и может превысить maxFileSize. FileMode::Truncate не удаляет старые архивы.

appendNewSession добавляет строку New session started с ID при каждой успешной инициализации файлового логгера. Маркер содержит обычные дату/время и выводится независимо от minimumLevel, даже Off; flush выполняется сразу. При false маркера нет. Как обычная запись, маркер учитывается при ротации.

| LogFolder | Основание пути |
|---|---|
| CurrentDirectory | Относительно текущей рабочей папки; абсолютный filePath также допустим |
| Application | Папка исполняемого файла EXE, не Diagnostic DLL |
| Package | Windows package LocalState; без package identity и на других ОС Initialize возвращает неуспешный LoggerInitResult |
| ApplicationOrPackage | В Windows LocalState при наличии package identity, иначе папка EXE |

Для выбора Application/Package путь должен быть относительным без ..; абсолютный путь передаётся с CurrentDirectory. Application реализован для Windows и Linux (/proc/self/exe), для других платформ задавайте полный путь явно. Папка EXE может быть недоступна для записи: ошибка открытия возвращает неуспешный LoggerInitResult. Package использует ApplicationPaths::GetPackageLocalDataDirectory() через Windows ApplicationData.LocalFolder; в текущей проверке подтверждён отказ для unpackaged EXE, запуск внутри установленного MSIX отдельно не проверен.

Initialize вызывается владельцем приложения; повторный вызов для активного ID возвращает неуспешный LoggerInitResult без изменения конфигурации. После Shutdown допускается повторная инициализация. SetLevel и ShouldLog работают до инициализации; начальный уровень Info. До Initialize и после Shutdown прошедшие фильтр сообщения выводятся напрямую в stderr без метаданных. Shutdown сохраняет текущий уровень фильтрации каждого ID. Ошибки инициализации возвращают неуспешный LoggerInitResult, остальные ошибки логирования не выходят исключениями в приложение. Резервный вывод best effort: ошибки самого stderr не восстанавливаются, параллельные резервные записи могут перемешиваться.

Макросы проверяют уровень до вычисления категории и аргументов. Log форматирует через std::format на стороне вызывающего модуля и перехватывает ошибки форматирования; Write принимает уже готовый текст и никогда не интерпретирует скобки как формат. Прямой вызов Log не предотвращает вычисление аргументов до входа в функцию. В DLL не передаются fmt/spdlog типы, владение строками или форматируемые пользовательские объекты. Публичный C++ ABI требует совместимых компилятора, STL и настроек сборки; это не универсальный C ABI.

Shutdown атомарно закрывает приём записей во все backend, ждёт уже допущенные операции Write/Flush, выполняет последний flush и освобождает logger/sink и файловые дескрипторы до возврата. Новые записи во время остановки проходят текущий фильтр и идут в fallback stderr, не ожидая вывода в закрывающийся backend. Initialize в этот период возвращает ShutdownInProgress без открытия/усечения файла. Параллельный Shutdown ждёт завершения уже начатой остановки; повторный вызов после остановки безопасен. Уровни ID сохраняются, повторная Initialize допускается после закрытия файлов. Граница допуска — получение backend в narrow Write или Flush, не начало вычисления аргументов/форматирования/Unicode-конверсии; ещё не допущенная запись может попасть в fallback. Shutdown не ждёт завершения вызовов, использующих только fallback. Перед выгрузкой DLL приложение всё равно обязано остановить все обращения к её API. Shutdown из операции backend или его callback не поддерживается: вызов отклоняется с диагностикой, чтобы не ждать самого себя. Минимальный объект синхронизации живёт до конца процесса для поздних статических деструкторов. Сервис не использует глобальный registry spdlog. После каждой записи выполняется синхронный flush, включая fallback; это не гарантирует физическую запись на носитель при сбое ОС или питания.

## Зависимость и сборка

`ThirdParty/spdlog` — Git submodule upstream gabime/spdlog, v1.16.0, commit `486b55554f11c9cccc913e11a87085b2a91f706f`. MIT license находится внутри submodule. Для нового checkout:

```text
git submodule update --init ThirdParty/spdlog
```

Сборка не скачивает исходники автоматически. CMake и MSBuild компилируют одинаковые upstream .cpp внутри Diagnostic DLL с SPDLOG_COMPILED_LIB. Сторонние заголовки и определения приватны компоненту; отдельные spdlog.dll и fmt.dll не нужны. Bundled fmt остаётся внутренней зависимостью. Сборочные hooks находятся в Projects/Cmake/Diagnostic/Spdlog.cmake и Projects/MsBuild/Diagnostic/Spdlog.targets. Общие генераторы и схема реестра не менялись.

## Debugger, консоль и контекст

LoggerOptions::enableDebugger добавляет Windows debugger sink (Visual Studio Output / Debug). На других ОС Initialize возвращает неуспешный LoggerInitResult при включённом enableDebugger. LoggerOptions::enableConsole добавляет stderr-консоль параллельно файлу/debugger. colorConsole=true включает автоматический выбор цвета для терминала; false отключает цвет. При перенаправлении цвет обычно отключается. Файловые и debugger-записи не содержат управляющих цветовых последовательностей. Если файл и дополнительные выходы не заданы, сохраняется прежний простой stderr. Каждый выход получает flush после сообщения.

```cpp
diagnostic::LoggerOptions loggerOptions;
loggerOptions.minimumLevel = diagnostic::Level::Debug;
loggerOptions.enableDebugger = true;
loggerOptions.enableConsole = true;
diagnostic::Logger::Initialize(loggerOptions);

class Worker {
    UDK_LOG_CLASS(Worker)
public:
    void Run() {
        UDK_LOG_FUNCTION_SCOPE_C();
        UDK_LOG_INFO_C("Working {}", 42);
        UDK_LOG_SCOPE_C("Load resource {}", 17);
    }
};

Worker worker;
worker.SetLogInstanceName("first");
worker.Run();
```

UDK_LOG_CLASS ставится в начале класса и добавляет LogContext и __LgCtx(); после макроса действует private, поэтому публичные объявления начинаются с public:. Контекст выводится как Worker[first]. Имя экземпляра задаётся до параллельного использования: SetLogInstanceName не синхронизирован. Макросы уровней с суффиксом _C берут this->__LgCtx(), с _S принимают явный LogContext первым аргументом для static-функций. Без макроса класса можно хранить LogContext самостоятельно и использовать _S.

UDK_LOG_FUNCTION_ENTER(category) пишет только вход. UDK_LOG_FUNCTION_SCOPE(category) пишет вход и выход; UDK_LOG_SCOPE(category, format, args...) позволяет задать имя операции; UDK_LOG_SCOPE_N(id, category, format, args...) выбирает ID. Варианты _C используют контекст объекта. Эти записи имеют уровень Debug; имя операции форматируется один раз при входе, аргументы не вычисляются при отключённом Debug. Scope пишет выход при обычном завершении, раннем return и раскрутке стека C++-исключением. Выход содержит длительность в микросекундах и пометку exception при новом активном исключении. Если уровень изменён внутри scope, выход может быть отфильтрован. LogScope нельзя копировать или перемещать; сам logger должен оставаться активным до завершения scope. Access violation, abort и принудительное завершение не гарантируют вызов деструктора. Макрос scope объявляет локальную переменную, используйте его внутри фигурных скобок, а не как одиночное тело if без скобок.

UDK_LOG_THREAD(name) ставится в начале функции потока: задаёт имя текущего потока, пишет Debug-запись Thread START и создаёт RAII ThreadScope, пишущий Thread END при выходе из области (включая return и раскрутку стека C++-исключением). UDK_LOG_THREAD_N(id, name) выбирает LoggerId. Имя вычисляется один раз и должно быть UTF-8. При отключённом Debug имя ОС всё равно задаётся, START/END не выводятся. Изменение фильтра внутри области может скрыть END. Windows использует SetThreadDescription (Windows 10 1607+); Linux/Android и macOS — pthread_setname_np. Linux ограничивает имя 15 байтами, macOS 63: обрезается только OS-имя на границе UTF-8, в логах остаётся полное. Ошибка переименования даёт Warning, не прерывая поток. Имя не восстанавливается при выходе. Макрос не создаёт поток и не является уведомлением ОС о его завершении: END означает выход из области, поэтому макрос надо ставить в области всей функции потока. ThreadScope нельзя копировать/перемещать; при access violation и принудительном завершении END не гарантируется. Поддержка Windows проверена запуском, POSIX-ветки на устройстве ещё не проверены.

```cpp
std::thread worker([] {
    UDK_LOG_THREAD("NetworkWorker");
    // Работа потока.
});
worker.join();
```

Diagnostic поддерживает narrow- и wide-форматы std::format. Обычные макросы, варианты _N/_C/_S и UDK_LOG_SCOPE принимают как "...", так и L"...". Для wide-формата подходят std::wstring и std::wstring_view в аргументах. Готовый wide-текст передаётся через Logger::Write(level, category, wideMessage). Категории и LogContext остаются UTF-8. Narrow- и wide-аргументы не смешиваются автоматически: допустимость определяется std::format. Форматные строки Log должны быть проверяемыми при компиляции; динамический std::wstring_view передаётся как готовое сообщение в Write, не как runtime-формат.

```cpp
UDK_LOG_INFO("Application", L"Открыт файл {}", std::wstring(L"документ.txt"));
UDK_LOG_SCOPE("Storage", L"Загрузка ресурса {}", 42);
diagnostic::Logger::Write(diagnostic::Level::Info, "Application", std::wstring_view(L"Готовое сообщение"));
```

Wide-сообщение сначала форматируется на стороне потребителя в std::wstring, затем DLL преобразует готовый текст в UTF-8 через Helpers/Text/Unicode.h. Backend и файлы остаются UTF-8, spdlog/fmt наружу не выставляются. Некорректный Unicode отклоняется; Write перехватывает ошибку и пытается записать диагностическое сообщение уровня Error с учётом текущего фильтра. Прямые wide-конструкторы LogScope/ThreadScope могут выбросить исключение преобразования; макросы перехватывают его. Имя потока также может быть std::wstring/std::wstring_view.

Для пользовательского типа обязателен явный std::formatter<T, char> и/или std::formatter<T, wchar_t>. Специализации располагаются в конце того же файла, где определён тип, после закрытия namespace типа. Можно использовать общую специализацию по CharT. Отдельные файлы форматтеров, автоматическое использование operator<< и произвольного ToString не добавляются. Форматтер использует стандартный <format>, не Diagnostic: циклической зависимости Helpers → Diagnostic нет. Старые fmt::formatter необходимо явно адаптировать к std::formatter. Для путей уже есть Helpers/StdExt/FormatSpecializations.h и stdext::Path(path); это отдельная существующая обёртка стандартного типа, а не fallback для произвольных объектов.

Папку EXE Diagnostic получает через Helpers/System/ApplicationPaths.h (приватная зависимость Helpers). GetPackageDirectory в этом helper означает папку установки UWP/MSIX; она не используется как writable-папка логов. Режимы LogFolder::Package и ApplicationOrPackage получают LocalState через ApplicationPaths::GetPackageLocalDataDirectory(); платформенный код из Logging.cpp удалён.

LoggerOptions — место для будущей конфигурации, Write — граница передачи записи в DLL. Backend полностью скрыт в Sources/Diagnostic/Logging.cpp. Контекст объекта и scope уже реализованы; async остаётся отдельным будущим этапом.