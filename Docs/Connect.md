# Connect: компоненты, варианты и зависимости

## Восстановление при ошибке

До изменения consumer и solution Connect сохраняет байтовые снимки в `<consumer.vcxproj>.UniversalDevKit.transaction`. При ошибке подключения или очистки solution оба файла восстанавливаются с исходной кодировкой и окончаниями строк. После успеха или завершённого отката снимки удаляются. Preview снимков не создаёт.

При неудачном откате снимки остаются на диске, сообщение перечисляет проблемные файлы. После аварийного завершения процесса повторный запуск обнаруживает незавершённую операцию и отказывается перезаписывать снимок. Закройте процессы, блокирующие файлы, и восстановите их с теми же путями:

```powershell
Import-Module ./Scripts/PowerShell/Modules/Module.Udk.Connection/Module.Udk.Connection.psm1
Restore-UdkConnectionTransaction -ProjectPath C:/Consumer/App.vcxproj -SolutionPath C:/Consumer/App.sln
```

Для ProjectOnly SolutionPath не передаётся. До восстановления проверяются пути и SHA-256 снимков. Каталог без manifest.json означает прерывание подготовки снимков до изменения consumer; его следует проверить вручную. Backup-файлы SolutionInjector и кеш инструмента не откатываются.

**Навигация:** [Главная](../README.md) → [Документация](README.md) → Connect

## Содержание

- [Управление и команды](#управление-и-команды)
- [HeleprsTest.Shared: отдельной библиотеки нет](#helpersshared-отдельной-библиотеки-нет)
- [HeleprsTest.Static: отдельная статическая библиотека .lib](#helpersstatic-отдельная-статическая-библиотека-lib)
- [HeleprsTest.Dynamic: импортная библиотека и DLL](#helpersdynamic-импортная-библиотека-и-dll)
- [DiagnosticTest.Shared: исходники зависимости](#diagnosticshared-исходники-зависимости)
- [DiagnosticTest.Static: зависимости доходят до линкера](#diagnosticstatic-зависимости-доходят-до-линкера)
- [DiagnosticTest.Dynamic: внутренняя статическая зависимость](#diagnosticdynamic-внутренняя-статическая-зависимость)
- [Прямой выбор HeleprsTest и конфликты](#прямой-выбор-helpers-и-конфликты)
- [Транзитивные DLL](#транзитивные-dll)
- [Публичные зависимости](#публичные-зависимости)
- [Новая зависимость в JSON](#новая-зависимость-в-json)
- [Проверки и ограничения](#проверки-и-ограничения)

Connect подключает UniversalDevKit к вашему C++-проекту Visual Studio/MSBuild. Далее этот проект называется приложением или потребителем (consumer), а solution — решением `.sln`. Исходники библиотеки остаются в UDK.

Для каждого выбранного компонента есть три режима:

- **Shared:** исходники UDK компилируются внутри вашего проекта.
- **Static:** UDK собирается отдельно в статическую библиотеку `.lib`; нужный код из неё включается в ваше приложение при сборке.
- **Dynamic:** код UDK находится в DLL; приложению нужны импортная `.lib` для сборки и DLL для запуска.

Зависимости берутся из реестра компонентов: `Components.json` и перечисленных в нём файлов `Projects/Components/*.json`. Ниже сценарии идут от простого к сложному. Блоки со стрелками показывают схемы сборки и зависимостей, а не исполняемый C++-код.

## Управление и команды

Запустите Scripts/Connect.cmd, выберите solution и consumer. Стрелки вверх/вниз выбирают компонент, влево/вправо — режим, Space отмечает выбор. Enter на Apply применяет изменения. Backspace возвращает назад, Esc отменяет выбор. Звёздочка обозначает транзитивный компонент. `/` или `.` показывает таблицу Depends on / Required by.

Connect / update добавляет компоненты или меняет их режимы; неотмеченные прежние корни сохраняются. Для удаления используйте Disconnect. Транзитивный компонент исчезает только после удаления последнего требующего его корня.

Несовместимые варианты отображаются красным с отметкой `[!]`. Проверка учитывает уже подключённые компоненты и текущие отметки; после изменения выбора доступность пересчитывается. На недоступный вариант можно перейти стрелками, чтобы прочитать причину, но Space не позволяет его отметить. Например, DiagnosticTest.Dynamic блокирует HeleprsTest.Dynamic, поскольку требует HeleprsTest.Static. Для ProjectOnly доступны только Shared-варианты. Если сохранённые подключения уже конфликтуют, Apply блокируется: исправьте режимы или удалите конфликтующий корень через Disconnect.

Пример неинтерактивного вызова из PowerShell:

```powershell
./Scripts/PowerShell/Connect.ps1 -SolutionPath C:/Path/App.sln -ProjectPath C:/Path/App.vcxproj -Components DiagnosticTest -ComponentModes @{ DiagnosticTest = 'Dynamic' }
```

ProjectOnly поддерживает Shared без изменения solution. Static/Dynamic требуют solution. После применения перезагрузите проекты в Visual Studio.

## HeleprsTest.Shared: отдельной библиотеки нет

Connect подключает Shared-проект HeleprsTest. Math.cpp и Text.cpp компилируются непосредственно в consumer с его настройками. Заголовки доступны через Includes/HeleprsTest и Includes/Core; остальные корни добавляются по графу зависимостей. PCH для исходников UDK отключён. Объектные файлы изолированы внутри IntDir/UniversalDevKit/.

```text
Main.cpp + Math.cpp + Text.cpp → Application.exe
```

## HeleprsTest.Static: отдельная статическая библиотека .lib

Connect добавляет в проект приложения `ProjectReference` — ссылку на проект HeleprsTest.Static. При сборке MSBuild сначала создаёт `HeleprsTest.Static.lib`, затем линкер объединяет код приложения с нужным кодом из этой библиотеки в `Application.exe`.

После сборки запускать приложение можно без HeleprsTest DLL. Отдельно копировать статическую `.lib` рядом с `.exe` тоже не нужно: она нужна только во время сборки.

```text
Math.cpp + Text.cpp → HeleprsTest.Static.lib
Main.obj + HeleprsTest.Static.lib → Application.exe
```

## HeleprsTest.Dynamic: импортная библиотека и DLL

Connect добавляет ссылку на проект HeleprsTest.Dynamic и определение `UNIVERSALDEVKIT_HELEPRSTEST_DYNAMIC`, чтобы заголовки объявляли функции как импортируемые из DLL.

Проект HeleprsTest.Dynamic создаёт два файла. `HeleprsTest.Dynamic.lib` — импортная библиотека: она позволяет линкеру приложения связать вызовы с функциями DLL. Реализация этих функций находится в `HeleprsTest.Dynamic.dll`, поэтому эта DLL должна быть доступна при запуске приложения. Это отличается от Static, где реализация включается в приложение.

Определение с суффиксом `_EXPORTS` используется только при сборке самой DLL; приложению Connect его не задаёт.

```text
HeleprsTest.Dynamic.lib → линковка Application.exe
HeleprsTest.Dynamic.dll → каталог запуска Application.exe
```

UniversalDevKit.Runtime.targets после успешной сборки запрашивает GetTargetPath библиотечных проектов и копирует DLL в OutDir. Путь к !artifacts не зашит в consumer: учитываются фактические TargetName, OutDir и переданные свойства MSBuild. Файлы копируются с SkipUnchangedFiles.

## DiagnosticTest.Shared: исходники зависимости

Реализация `DiagnosticTest::Log` вызывает функцию `EndsWithLineBreak` из HeleprsTest. Поэтому одного `Logging.cpp` недостаточно.

Если выбрать DiagnosticTest.Shared, Connect добавит в приложение исходники и DiagnosticTest, и HeleprsTest. Отдельные `.lib` и DLL для них не создаются. Даже если HeleprsTest нужен нескольким компонентам, его исходники добавляются один раз. Поле `linkage` из JSON относится к бинарным вариантам; при Shared все зависимости подключаются исходниками.

```text
Main.cpp + Logging.cpp + Math.cpp + Text.cpp → Application.exe
```

visibility не исключает приватные исходники: они всё равно нужны реализации. При ProjectOnly Sources.targets раскрывает актуальный граф во время вычисления MSBuild. Обычное подключение через solution сохраняет конкретные Shared References и требует обновления после изменения JSON.

## DiagnosticTest.Static: зависимости доходят до линкера

В JSON указано, что DiagnosticTest использует HeleprsTest внутри своей реализации (`visibility=private`) и требует статический вариант HeleprsTest (`linkage=static`).

Создаются две отдельные библиотеки: `DiagnosticTest.Static.lib` содержит код DiagnosticTest, а `HeleprsTest.Static.lib` — код HeleprsTest. Код HeleprsTest не добавляется внутрь самой `DiagnosticTest.Static.lib`.

При создании приложения линкеру нужны обе `.lib`: из DiagnosticTest он получает `Log`, а из HeleprsTest — вызываемую ей `EndsWithLineBreak`. Connect подключает обе библиотеки, даже если пользователь выбрал только DiagnosticTest.Static.

```text
Application.exe ← DiagnosticTest.Static.lib + HeleprsTest.Static.lib
DiagnosticTest.Static.vcxproj → HeleprsTest.Static.vcxproj (порядок сборки)
```

`private` означает, что HeleprsTest нужен внутреннему коду DiagnosticTest. Это не означает, что его `.lib` можно исключить из сборки приложения: иначе линкер не найдёт реализацию `EndsWithLineBreak`.

В ссылках приложения на необходимые библиотеки Connect задаёт `LinkLibraryDependencies=true`. В ссылках между Static-проектами используется `false`: зависимость обеспечивает порядок сборки, а статические библиотеки остаются отдельными.

## DiagnosticTest.Dynamic: внутренняя статическая зависимость

Если выбрать DiagnosticTest.Dynamic, `linkage=static` всё равно требует HeleprsTest.Static.

Сначала собирается `HeleprsTest.Static.lib`. Затем при создании DiagnosticTest DLL нужный код HeleprsTest включается в `DiagnosticTest.Dynamic.dll`. Приложение использует импортную `DiagnosticTest.Dynamic.lib` и запускается с `DiagnosticTest.Dynamic.dll`.

```text
DiagnosticTest.Dynamic.dll ← Logging.obj + HeleprsTest.Static.lib
Application.exe ← импортная DiagnosticTest.Dynamic.lib
Файлы запуска: DiagnosticTest.Dynamic.dll
```

Приложению не нужно отдельно подключать HeleprsTest для вызова `DiagnosticTest::Log`: необходимый код HeleprsTest уже находится в DiagnosticTest DLL. Отдельная HeleprsTest DLL из-за этой зависимости не создаётся, а макрос импорта HeleprsTest приложению не передаётся.

Однако это не даёт приложению прямого доступа к функциям HeleprsTest через DiagnosticTest DLL. Если приложение само вызывает `IsPowerOfTwo`, HeleprsTest нужно выбрать отдельно, например в режиме Static.

Для порядка сборки Connect также добавляет ссылки на внутренние проекты с `LinkLibraryDependencies=false`. Такая ссылка сохраняет проект зависимости в solution, но не подключает его `.lib` к линкеру приложения.

## Прямой выбор HeleprsTest и конфликты

DiagnosticTest.Dynamic + HeleprsTest.Static допустимы: обе цепочки требуют Static-вариант HeleprsTest. Приложение самостоятельно использует HeleprsTest и получает прямую статическую ссылку.

DiagnosticTest.Dynamic + HeleprsTest.Dynamic отклоняются: одна цепочка требует HeleprsTest.Static, другая — HeleprsTest.Dynamic. Аналогично запрещено сочетание HeleprsTest.Shared с бинарной зависимостью HeleprsTest.Static. Ошибка показывает оба режима и пути в графе; проверка выполняется до записи solution и consumer.

Это консервативная политика: один вариант на имя компонента во всём графе одного consumer. Две реализации компонента без состояния технически могут работать, но такая комбинация пока не поддерживается. Совпадение режима не гарантирует единый экземпляр состояния во всём процессе: статический код может присутствовать в нескольких DLL. Сервисы с состоянием должны отдельно определять владение и время жизни.

## Транзитивные DLL

Предположим, будущий DiagnosticTest зависит от Formatting с linkage=same, а Formatting — от HeleprsTest с linkage=static. Для Dynamic корня получится:

```text
Application → DiagnosticTest.Dynamic → Formatting.Dynamic → HeleprsTest.Static
```

При `visibility=private` приложение использует импортную библиотеку DiagnosticTest. Но при запуске DiagnosticTest DLL сама обращается к Formatting DLL. Поэтому рядом с приложением нужны **обе DLL**, хотя пользователь выбрал только DiagnosticTest.

HeleprsTest.Static используется при создании Formatting DLL: нужный код включается в неё, а файл HeleprsTest.Static.lib рядом с приложением не копируется.

RuntimeComponents рассчитывается по всему графу, включая private-зависимости любой глубины, с устранением повторов. Для consumer, который сам является DLL, OutDir обозначает каталог этой DLL; окончательное приложение должно также получить runtime-набор. Connect не управляет поиском DLL загрузчиком и не доставляет сторонние runtime-библиотеки, не описанные компонентами UDK.

## Публичные зависимости

visibility=public означает, что публичные требования зависимости передаются потребителю. Например, если публичный интерфейс DiagnosticTest использует динамический Formatting, consumer получает его import-макрос и ссылку. public-цепочки раскрываются транзитивно; private-цепочка прерывает передачу публичных требований.

Все текущие заголовки доступны через общий Includes. Специальные внешние include-пути и произвольные compile options реестр компонентов пока не описывает. Для CMake PUBLIC/PRIVATE передаются target_link_libraries и учитываются стандартным механизмом usage requirements.

## Новая зависимость в JSON

Описание ребра:

```json
{
  "component": "HeleprsTest",
  "visibility": "private",
  "linkage": "static"
}
```

component — имя компонента. visibility допускает private/public. linkage допускает static/same/dynamic: static выбирает Static для бинарной зависимости, same наследует вариант родителя, dynamic требует Dynamic. При Shared same/static подключаются исходниками, dynamic остаётся библиотечной зависимостью. stateScope=process запрещает Shared/Static для самого сервиса; подробнее — [общее состояние](StateScope.md).

GenerateComponentProjects формирует Shared-списки, Sources.targets и файлы *.Dependencies.props для библиотечных проектов. Последние импортируются Static/Dynamic-проектами. CMake читает тот же JSON, сначала создаёт все компонентные targets, затем связывает их согласно visibility/linkage. Межкомпонентные связи не следует дублировать вручную. Стандарт C++, потоки и системные библиотеки также задаются в JSON; адаптеры описаны в [Requirements](Requirements.md).

Для нового компонента создайте заголовки, исходники, JSON-описание и добавьте его в Components.json. Генератор создаёт отсутствующие Static/Dynamic vcxproj по шаблону с импортами Shared.vcxitems и Dependencies.props. GUID новых вариантов детерминированы по msbuildGuid и режиму; существующие проекты сохраняются, а обязательные импорты и GUID проверяются. Генератор добавляет отсутствующие записи проектов в собственный solution UDK. CMake создаёт обычные компонентные targets непосредственно из JSON; отдельный файл компонента нужен только для специальных настроек. Неизвестные зависимости, циклы и конфликты вариантов останавливают расчёт.

После изменения реестра компонентов:

1. Запустите GenerateComponentProjects.cmd.
2. Выполните GenerateComponentProjects.cmd -Check.
3. Повторите Connect для consumer, чтобы обновить ссылки, определения и runtime-набор.
4. Соберите и запустите consumer в нужных конфигурациях.

Обычное подключение сохраняет SHA-256 корневого реестра компонентов и всех включённых описаний. Перед PrepareForBuild проверяются отпечатки: изменение любого JSON останавливает сборку с предложением повторить Connect. Даже изменение форматирования требует обновления. Это обнаружение устаревшего реестра компонентов, а не полноценный Check/Repair ручных изменений vcxproj. Для старых подключений проверка появляется после повторного Connect.

## Проверки и ограничения

Connect.Tests.ps1 проверяет графы Shared/Static/Dynamic, публичные и приватные зависимости, транзитивные DLL, конфликты, циклы, неизвестные компоненты и Disconnect. Invoke-UdkConnectionPlan -Preview возвращает рассчитанное XML consumer без изменения файлов и без запуска SolutionInjector; нужные Shared-проекты уже должны присутствовать в указанном solution. GenerateComponentProjects.ps1 -PassThru возвращает план генерации без записи.

Совместимость архитектуры, конфигурации и CRT обязательна. Текущие библиотечные проекты поддерживают Windows x64 Debug/Release. Connect работает с проектами из checkout UDK, а не с установленными NuGet/AAR или произвольными готовыми бинарниками. Он не удаляет старые DLL из OutDir после переключения режима: для проверки чистого runtime-набора используйте чистый каталог сборки. Полный Check/Repair, транзакционное изменение solution/consumer и кеш распакованного SolutionInjector остаются отдельными задачами.