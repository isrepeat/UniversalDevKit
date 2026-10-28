# Сборка через MSBuild

**Навигация:** [Главная](../README.md) → [Документация](README.md) → MSBuild

## Содержание

- [Собрать UDK отдельно](#собрать-udk-отдельно)
- [Подключить consumer](#подключить-consumer)
- [Как собирается Shared](#как-собирается-shared)
- [Как собирается Static](#как-собирается-static)
- [Как собирается Dynamic](#как-собирается-dynamic)
- [Режим ProjectOnly](#режим-projectonly)
- [Использовать только заголовки](#использовать-только-заголовки)
- [Обновления и платформы](#обновления-и-платформы)

## Собрать UDK отдельно

Откройте UniversalDevKit.sln в Visual Studio с установленными средствами разработки C++. Выберите Debug/Release и x64, затем соберите нужный Static/Dynamic-проект. Shared-проекты содержат файлы для импорта и самостоятельно не компилируются.

Из Developer PowerShell или Developer Command Prompt:

```powershell
msbuild UniversalDevKit.sln /m /p:Configuration=Release /p:Platform=x64
```

Результаты собственных проектов направляются через BuildLayout.props в `!artifacts/Windows-x64/msbuild/<toolset>/<версия компилятора>/<md или mt>/<компонент.вариант>/<конфигурация>/bin/`, промежуточные файлы — в obj/. Публичный UniversalDevKit.props не меняет каталоги consumer.

UniversalDevKitRuntime выбирает CRT независимо от Static/Dynamic компонента. При бинарном подключении без явного значения CRT определяется по RuntimeLibrary consumer: /MD(d) выбирает Dynamic, /MT(d) — Static. Явное значение должно совпадать с consumer и его Debug/Release-конфигурацией. CRT, PlatformToolset и VCToolsVersion передаются библиотечным ссылкам и запросам TargetPath. Два consumer одного solution могут использовать разные CRT; импортированные библиотеки собираются через consumer, а не отдельно с настройками solution. Shared сохраняет CRT consumer. Разные toolset, версии компилятора и CRT получают отдельные каталоги; произвольные сочетания toolset не считаются проверенными.

## Подключить consumer

Scripts/Connect.cmd позволяет выбрать solution, проект и режим каждого компонента. Connect меняет .sln и .vcxproj; эти изменения сохраняются в репозитории consumer. После Apply перезагрузите solution. Исходники остаются в UDK, поэтому относительное расположение checkout и consumer должно сохраняться.

Подробные клавиши, команды, переключения и Disconnect находятся в [Connect](Connect.md).

## Как собирается Shared

Connect добавляет импорты выбранных Shared.vcxitems и транзитивных компонентов. MSBuild добавляет их ClCompile в проект consumer. Они компилируются с настройками consumer, с отключённым PCH и отдельными объектными путями в `$(IntDir)UniversalDevKit/`.

Заголовки подключаются через UniversalDevKit.props. Стандарт C++20 или выше consumer задаёт сам. Shared References в solution нужны также для отображения связи в Visual Studio.

## Как собирается Static

Connect добавляет ProjectReference на библиотечные проекты. MSBuild строит зависимости и передаёт требуемые .lib финальному линкеру. Сгенерированные Dependencies.props описывают межкомпонентные связи.

Статические архивы UDK не объединяются автоматически в один архив. Например, DiagnosticTest.Static содержит свою реализацию, а consumer должен получить также HeleprsTest.Static. Connect рассчитывает этот набор; у библиотечных ссылок различается LinkLibraryDependencies в зависимости от роли проекта.

## Как собирается Dynamic

DLL-проект компилируется с UNIVERSALDEVKIT_<КОМПОНЕНТ>_DYNAMIC и _EXPORTS. Consumer получает только _DYNAMIC, чтобы объявления использовали dllimport. _EXPORTS задавать consumer нельзя.

Consumer линкуется с импортной .lib, а реализация выполняется из DLL. UniversalDevKit.Runtime.targets после успешной сборки получает GetTargetPath всех необходимых DLL-проектов и копирует файлы в `$(OutDir)`. При consumer-DLL итоговое приложение также должно обеспечивать обнаружение всего runtime-набора загрузчиком.

## Режим ProjectOnly

```powershell
./Scripts/PowerShell/Connect.ps1 -ProjectOnly -ProjectPath C:/Projects/App/App.vcxproj -Components DiagnosticTest
```

Этот режим изменяет только .vcxproj и поддерживает Shared. Sources.targets раскрывает зависимости во время вычисления проекта. Static/Dynamic через ProjectOnly сейчас не поддерживаются.

## Использовать только заголовки

После Microsoft.Cpp.props импортируйте публичные настройки:

```xml
<Import Project="..\external\UniversalDevKit\Projects\MsBuild\UniversalDevKit.props" />
```

Импорт добавляет Includes и сохраняет существующие include-пути. Он не добавляет .cpp, библиотеки, язык C++ или CRT. Наличие UDK в solution само по себе не подключает его к consumer.

## Обновления и платформы

После изменения JSON выполните GenerateComponentProjects, затем повторите обычный Connect. Runtime.targets сравнивает сохранённые SHA-256 JSON перед компиляцией; даже изменение форматирования реестра требует обновления подключения.

UniversalDevKitTargetOS по умолчанию равен Windows. Оно выбирает platformSources и проверяет supportedPlatforms. Переопределение свойства не переключает Windows toolchain на Linux/Android; текущие библиотечные проекты проверены только для Windows x64.

Ошибки ручных изменений consumer, восстановление при сбое, старые DLL и совместимость CRT рассматриваются в [проверках и ограничениях](Validation.md).