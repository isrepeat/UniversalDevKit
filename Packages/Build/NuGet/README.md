# Native NuGet для Windows

## Подготовка внешних зависимостей

Поле `dependencyName` в delivery задаёт читаемое имя рабочего каталога подготовщика; для OpenGLESRenderer это `ANGLE`. При отсутствии поля сохраняется имя компонента. Таким образом, ANGLE находится в `!artifacts/packages/nuget/<root-component>/dependencies/ANGLE/<runtime>`. Параметры `Preparations` по-прежнему адресуются по компоненту и CRT: имя каталога не меняет контракт staging. При повторной настройке подготовленного ANGLE упаковщик сбрасывает кеш результатов поиска заголовков и библиотек, чтобы перенос установки не оставлял ссылок на прежний путь.

Промежуточное дерево vcpkg называется `buildtrees` (ранее `b`). Новые запуски используют читаемое имя; старый каталог `b` автоматически не переносится и не удаляется. После остановки сборок его можно удалить. Некоторые инструменты раскрывают `subst` в физический путь, поэтому для глубоко вложенного репозитория ограничение длины пути всё ещё возможно.

Общая структура каталогов описана в [Артефактах](../../../Docs/Artifacts.md). Staging получает словарь `Preparations`: для каждого поддерживаемого CRT в нём доступны параметры, возвращённые подготовщиком. Это позволяет копировать зависимости из текущей рабочей сборки без настройки глобальных переменных окружения.

Необязательное поле `preparationScript` в `Delivery/NuGet/Delivery.json` задаёт путь к `.ps1` относительно этого delivery. Скрипт должен находиться внутри каталога своего пакета. Он выполняется для выбранного компонента и его транзитивных зависимостей перед CMake configure, отдельно для поддерживаемых CRT-профилей `Dynamic` (MD/MDd) и `Static` (MT/MTd).

Подготовщик получает параметры `RepositoryPath`, `WorkDirectory`, `Runtime`, `Configurations` (Debug и Release) и `Generator`. Целевая платформа этого адаптера — Windows x64. Постоянный `WorkDirectory` находится в `!artifacts/packages/nuget/<root-component>/dependencies/<dependencyName>/<runtime>` и не очищается упаковщиком. Проверка актуальности результатов, применение патчей и использование кеша относятся к реализации подготовщика; само наличие рабочего каталога не означает попадание в кеш.

Единственный результат в success stream — словарь строковых CMake-параметров, например `@{ UniversalDevKitExampleRoot = $preparedRoot }`; при отсутствии параметров возвращается пустой словарь `@{}`. Сообщения выводятся через `Write-Host`/`Write-Verbose`, вывод внешних утилит направляется в `Out-Host`. При ошибке скрипт обязан вызвать `throw`, в том числе после проверки кода завершения внешней утилиты. Подготовщик не должен менять глобальное окружение процесса.

Ключи словаря начинаются с `UniversalDevKit` и содержат только ASCII-буквы, цифры и `_`. Изменение параметров выбора компонентов, CRT и release policy запрещено. Результаты объединяются и передаются текущему CMake configure через `-D`; несовпадающие значения одного ключа отклоняются до configure. Результаты разных CRT-профилей не смешиваются.

`preparationScript` подготавливает зависимости до сборки, а существующий `stagingScript` дополняет содержимое `payload` после сборки, перед NuGet pack. OpenGLESRenderer подключает `PrepareAngle.ps1`: он использует закреплённый manifest и overlay из `ThirdParty/XamlRuntime/ANGLE`, устанавливает ANGLE через vcpkg для `x64-windows` (Dynamic CRT, Debug/Release) и возвращает `UniversalDevKitAngleRoot` в CMake. Упаковка ANGLE пока остаётся прежней и использует `UDK_ANGLE_ROOT`.

Подготовщик находит vcpkg через `VCPKG_ROOT`, PATH или Visual Studio. Installed-дерево, buildtrees и packages сохраняются в рабочем каталоге компонента. Кеш загрузок находится в `!artifacts/cache/vcpkg/downloads`; binary cache по умолчанию — `!artifacts/cache/vcpkg/binaries`. Заданный `VCPKG_BINARY_SOURCES` сохраняет приоритет, включая пользовательское отключение кеша. vcpkg проверяет актуальность установленных пакетов и ABI с учётом overlay и патчей; собственных маркеров «уже собрано» подготовщик не использует. Перед возвратом проверяются заголовки, лицензия, DLL/LIB EGL/GLES и DLL zlib для обеих конфигураций. ANGLE всегда собирается с коротким путём через временный `subst`, который освобождается при завершении или ошибке.

Diagnostic выпускается командой `Scripts/Packages/CrossPlatform/Pack.Diagnostic.cmd` либо `Build.ps1 -Components Diagnostic -LicenseFile ./LICENSE`. Пакет `UniversalDevKit.Diagnostic` содержит только Dynamic-вариант логгера (DLL/import library), Debug/Release, MD/MDd; Helpers восстанавливается как private-зависимость. Потребитель задаёт `UniversalDevKitComponents=Diagnostic`; `UniversalDevKitDiagnosticLinkage` по умолчанию Dynamic, Static/Shared отклоняются. DLL копируется рядом с приложением штатным targets. Проверка отдельного пакета: `Tests/Integration/Packages/NuGet.PackageReference.Tests.ps1 -Components Diagnostic -Feed <local-feed>`. Необязательное поле supportedRuntimes в Delivery.json ограничивает состав CRT-профилей пакета; для Diagnostic разрешён только Dynamic. MT запрещён из-за передачи C++-объектов с динамической памятью через границу DLL.

Собственные nuspec, props и targets находятся непосредственно в Delivery/NuGet каждого пакета. Nuspec может использовать плейсхолдеры версии и зависимостей `{{VERSION}}` и `{{DEPENDENCIES}}`; props/targets копируются без подстановок. Выражения MSBuild `$(Property)` и `%(Metadata)` вычисляются у consumer. Штатные CMake-шаблоны не изменяются.

Build.ps1 читает Components.json и выпускает пакет UniversalDevKit.<компонент> для каждого выбранного компонента и его транзитивных зависимостей. Без Components выбирается весь реестр. Версия берётся из Version.json, NuGet-зависимости требуют точную версию выпуска. Имена компонентов и связи не зашиты в упаковщик.

Для каждого выбранного компонента требуется описание Packages/<категория>/<пакет>/Package.json. Поле component связывает адаптер с реестром UDK; deliveries.NuGet указывает Delivery/NuGet/Delivery.json с package ID и supportedPlatforms. Идентификатор пакета может отличаться от имени компонента. Текущий адаптер component упаковывает один компонент в пакет; составные и инструментальные адаптеры пока не реализованы.

В Delivery.json поле nuspec задаёт собственный манифест, а integration — targets и необязательный props относительно Delivery/NuGet. В них можно добавлять индивидуальные файлы, targets, проверки и imports. Вспомогательные props/targets рядом с основным targets и ресурсы в подкаталогах копируются с сохранением структуры; Delivery.json и nuspec в build/native не копируются.

Build.ps1 создаёт build/native/Generated/Settings.props с версией и параметрами совместимости и Settings.targets с рассчитанными ссылками, требованиями и проверками графа. Собственные props/targets явно импортируют эти файлы; пути к зависимым пакетам должны быть объявлены до вычисления Settings.targets. Generated — зарезервированный каталог, исходные файлы туда не помещаются. Общих шаблонов nuspec/props/targets нет.

```powershell
./Packages/Build/NuGet/Build.ps1 -LicenseFile ./LICENSE
./Packages/Build/NuGet/Build.ps1 -Components DiagnosticTest -LicenseFile ./LICENSE
./Tests/Integration/Packages/NuGet.Tests.ps1 -LicenseFile ./LICENSE
./Tests/Integration/Packages/NuGet.Registry.Tests.ps1
```

Поддерживаются Windows x64, текущий MSVC compiler/toolset, Debug/Release, MD/MDd. Пакеты compiled содержат библиотеки Static/Dynamic согласно доступным вариантам; process-компоненты требуют Dynamic. Header-only компоненты подключаются в режиме Shared без компиляции исходников и искусственных бинарников. Пакеты не публикуются, локальный feed каждого корня сохраняется под `!artifacts/packages/nuget/<root-component>`. Здесь находятся пакеты корня и зависимостей, `build/<runtime>`, `install/<runtime>`, `staging/<component>` и `build.log`. Разные корни допускают параллельный запуск; повторный запуск одного корня блокируется. При передаче `OutputDirectory` к нему также добавляется имя корня.

LicenseFile обязателен, его текст включается как LICENSE.txt. CMake обнаруживается в Visual Studio либо задаётся параметром CMake. RepositoryPath позволяет тестировать другой реестр в изолированной копии. Повторная упаковка создаёт новый staging, чтобы исключить устаревшие файлы.

## Подключение consumer

Первый проверенный путь использует packages.config. NuGet в Visual Studio добавляет imports build/native/UniversalDevKit.<компонент>.props и .targets; restore восстанавливает файлы, но не создаёт imports в вручную написанном vcxproj. Все props импортируются до всех пакетных targets. Это обеспечивает доступность корней транзитивных пакетов независимо от порядка targets.

Consumer явно задаёт корневые компоненты в UniversalDevKitComponents, например DiagnosticTest;HeleprsTest. Пакеты, доставленные как зависимости, автоматически не становятся корнями. UniversalDevKit<компонент>Linkage выбирает вариант корня; по умолчанию Static, для process — Dynamic, для headerOnly — Shared. UniversalDevKitRuntime выбирает Dynamic (MD) или Static (MT), по умолчанию Dynamic. Consumer выбирает C++20 или более новый необходимый стандарт самостоятельно; его RuntimeLibrary пакет не меняет.

Ссылки финального линкера, import-макросы, публичные include-пути, системные библиотеки и транзитивные DLL вычисляются Resolve-UdkLinkageGraph, используемым Connect. Пересекающиеся графы корней проверяются на конфликт вариантов. Например, DiagnosticTest требует private/static HeleprsTest: отдельный корень HeleprsTest.Dynamic конфликтует с ним, а DiagnosticTest.Dynamic без корня HeleprsTest не линкует HeleprsTest.Static в приложение.

Метаданные установленного выпуска включаются в binaries/<runtime>/<configuration>/Release.json. Принудительно подключённый Abi.h проверяет фактический CRT, конфигурацию, iterator debug level и точную версию компилятора; targets проверяет VCToolsVersion/toolset и версии зависимостей. Другие платформы пока не проверены.

## Native PackageReference

Для native vcxproj с поддерживающим MSBuild включите экспериментальную возможность EnableNativePackageReferenceSupport. Проверено на Visual Studio 2026/MSBuild 18.11; на старых версиях используйте packages.config. Статус и ограничения возможности описаны в [документации команды Microsoft C++](https://devblogs.microsoft.com/cppblog/nuget-packagereference-for-c-projects-in-visual-studio/).

В Globals до импорта Microsoft.Cpp.Default.props задайте:

```xml
<PropertyGroup Label="Globals">
  <EnableNativePackageReferenceSupport>true</EnableNativePackageReferenceSupport>
  <UniversalDevKitComponents>DiagnosticTest</UniversalDevKitComponents>
  <UniversalDevKitRuntime>Dynamic</UniversalDevKitRuntime>
  <UniversalDevKitDiagnosticTestLinkage>Dynamic</UniversalDevKitDiagnosticTestLinkage>
</PropertyGroup>
<ItemGroup>
  <PackageReference Include="UniversalDevKit.DiagnosticTest" Version="[0.1.0]" />
</ItemGroup>
```

Замените версию на нужный выпуск. Восстановление: MSBuild Consumer.vcxproj /t:Restore /p:Configuration=Debug /p:Platform=x64. После него сборка выполняется обычным MSBuild. NuGet.Config определяет feed; ручные imports пакетов и packages.config не нужны. RuntimeLibrary самого consumer должен соответствовать выбранному UniversalDevKitRuntime, как и при старом способе подключения.

Упаковщик создаёт buildTransitive/native/<package ID>.props/.targets, импортирующие штатную интеграцию из build/native. Поэтому восстановленные зависимости автоматически объявляют свои корни и версии до вычисления графа, но не становятся корнями UniversalDevKitComponents и не передают private include-пути/import-макросы. Линковка, ABI-проверки и копирование runtime используют ту же реализацию, что и packages.config.

Проверка реальных HeleprsTest/DiagnosticTest: Tests/Scripts/RunNuGetPackageReferenceTests.cmd либо NuGet.PackageReference.Tests.ps1. Каждый consumer восстанавливается в собственный кеш из локального feed; проверяются project.assets.json, точные версии зависимостей, Static/Dynamic, MD/MT, Debug/Release, приватные требования, DLL и чистый запуск. Ошибочный CRT и неподдерживаемый вариант должны отклоняться. Параметр -Feed позволяет проверить уже собранные пакеты.

Полная матрица Diamond с двумя consumer и конфликтами: Tests/Integration/Cmake/Diamond.Tests.ps1 -Delivery NuGet -PackageReference. Все шесть графов используют один корневой PackageReference на приложение; транзитивные зависимости и DLL приходят из пакетов автоматически. Общий runner содержит NativePackageReference и DiamondPackageReference.

NuGet pack может выдавать NU5128 для группы native без managed lib/ref: native-библиотеки намеренно подключаются через targets.