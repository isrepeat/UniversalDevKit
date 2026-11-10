# Универсальный инструмент выпуска пакетов

**Навигация:** [Документация](README.md) → Выпуск пакетов

UDK выпускает UniversalDevKit.PackageTools как самостоятельный NuGet. Реализация находится в Sources/Windows/PackageTools; пакет содержит все адаптеры, helpers, manifest NuGet.exe и MSBuild targets. Использование инструмента не требует checkout UDK. AndroidAppPreviewer — отдельный репозиторий и самостоятельный владелец выпуска Previewer/PluginSDK.

## Подключение к другому репозиторию

Создайте служебный Packages/Build.csproj с закреплённым PackageReference:

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <EnableDefaultItems>false</EnableDefaultItems>
    <UdkPackageRepository>$(MSBuildProjectDirectory)/..</UdkPackageRepository>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="UniversalDevKit.PackageTools" Version="0.5.0" PrivateAssets="all" />
    <UdkPackage Include="Packages/MyLibrary/Package.json" />
  </ItemGroup>
</Project>
```

Команды из корня потребителя:

```powershell
dotnet msbuild Packages/Build.csproj -restore -t:PlanRepositoryPackages
dotnet msbuild Packages/Build.csproj -restore -t:PackRepository
```

Первое действие проверяет JSON без сборки проектов, второе создаёт NuGet локально. Отправку пакетов в feed выполняет отдельное действие CI. Для восстановления инструмента используются стандартные NuGet.Config и RestoreAdditionalProjectSources. UdkPackageSources задаёт источники для адаптера nuget-restore. Дополнительные свойства: UdkPackageOutput, UdkPackageNuGet, UdkPackageCMake, UdkPackagePowerShell.

В установленном пакете также можно напрямую вызвать tools/Build.ps1 с RepositoryPath и PackagePath. Исходная точка UDK Packages/Build/Build.ps1 — только оболочка над тем же инструментом.

## Контракт проектов

Поле projects в Package.json допускает два варианта. Основной — объект локальных определений: ключ задаёт имя проекта, значение содержит adapter и параметры адаптера. name и schemaVersion внутри локального проекта не указываются. Необязательные dependencies ссылаются на другие ключи того же объекта. Для общих проектов сохранён прежний вариант: строка с путём реестра Projects/Build.json версии 1, который перечисляет отдельные файлы через includes; внешние проекты сохраняют явные schemaVersion=1 и name. Сборщик выполняет выбранные проекты и их зависимости в топологическом порядке; циклы и неизвестные зависимости отвергаются.

Пути внутри проекта относительны к корню собираемого репозитория. Адаптер предоставляет именованные корни результатов, например output, build или install. Состав пакета выбирает файл или каталог непосредственно через root/path в contents. Поля projects.<имя>.artifacts и contents.artifact удалены из контракта и отклоняются как неизвестные поля, включая проекты внешнего реестра.

| Адаптер | Параметры и корни результатов |
|---|---|
| dotnet | project (.csproj), operation (build/publish), configuration (Debug/Release), необязательные runtime и selfContained. Корень output. selfContained требует publish с runtime. |
| cmake-install | sourceDirectory, generator, architecture, configurations, parallel, variables. Корень install; CMAKE_INSTALL_PREFIX задаёт адаптер. |
| component-sources | component (JSON со списками headers/sources), sourceRoot, includeRoot, publicHeaders, headerDestination, sourceDestination, manifestDestination. Корень output. |
| files | mappings с source и destination. Директория переносится содержимым; у файла destination задаёт полный путь. Корень output. |
| nuget-restore | id, точная version, необязательный массив sources. Корень package содержит восстановленный пакет. Глобальный PackageSources имеет приоритет над sources. |

component-sources берёт только явно перечисленные headers/sources; platformSources пока отвергается. publicHeaders выбирает публичные заголовки относительно sourceRoot; * и ? не пересекают /. Остальные заголовки размещаются рядом с реализацией. Этот адаптер не требует C++ генератора UDK.

cmake-install допускает preparation для нестандартной подготовки зависимости: script, parameters и properties. Hook получает RepositoryPath, WorkDirectory, Configurations, Generator и дополнительные parameters; возвращает hashtable объявленных properties с существующими каталогами. Свойства передаются CMake и становятся корнями результатов. Их можно передать через Properties напрямую. Подготовка ANGLE остаётся специализированным hook существующего пакета OpenGLESRenderer, а не частью ядра инструмента.

Для нового адаптера согласованно расширяются reader Private/Contract.ps1, диспетчеризация Build.ps1 и реализация Adapters. Обычный новый пакет не требует нового адаптера.

## Контракт пакета

Package.json версии 2 содержит name, versionSource, projects, непустой contents и deliveries с именованными способами доставки. Пути versionSource и deliveries относительны к каталогу пакета. contents.source относителен корню репозитория. Для пакета только из готовых файлов projects может быть пустым объектом. Если projects — строка, путь внешнего реестра относителен каталогу пакета; пути внутри любых определений проектов по-прежнему относительны корню репозитория.

```json
{
  "schemaVersion": 2,
  "name": "MyLibrary",
  "versionSource": "../../Version.json",
  "projects": {
    "managed": {
      "adapter": "dotnet",
      "project": "MyLibrary/MyLibrary.csproj",
      "operation": "build",
      "configuration": "Release"
    }
  },
  "contents": [
    { "project": "managed", "root": "output", "path": "MyLibrary.dll", "destination": "lib/net8.0" },
    { "source": ".", "include": ["LICENSE"], "rename": { "LICENSE": "LICENSE.txt" }, "destination": "." }
  ],
  "deliveries": { "NuGet": "Delivery/NuGet/Delivery.json" }
}
```

destination всегда задаёт каталог внутри payload, точка означает его корень. Каталог копируется содержимым с сохранением относительной иерархии по умолчанию; файловый результат проекта сохраняет имя. rename позволяет изменить имена файлов. Выход путей за границы корня, конфликты имён, отсутствующие результаты и пустой отбор приводят к ошибке.

Delivery.json версии 1 выбирает adapter=nuget, id, supportedPlatforms=["Windows"], nuspec и необязательный noWarn. Необязательный dependencies содержит элементы id/version с точной версией без диапазона. Nuspec должен содержать {{DEPENDENCIES}}; адаптер заменяет его на dependency с точным диапазоном [version]. Повторы, ссылка на сам пакет и несовпадение placeholder с описанием отвергаются. Адаптер проверяет ID nuspec, подставляет {{VERSION}} и упаковывает готовый payload. Стандартная запись files в nuspec: payload\**\* → корень пакета.

Все продуктовые Package.json UDK переведены на schemaVersion: 2. Старые упаковщики удалены. Версия Delivery.json остаётся 1: это отдельный контракт доставки, а не версия Package.json. Выбор выполняется параметром -Delivery; без него выбирается NuGet либо единственная доставка.

## Отбор файлов в contents

В PackageTools 0.4.0 отбор выполняется только напрямую в contents: root по умолчанию равен output, path — точке. Для CMake укажите root=build или root=install, для nuget-restore — root=package. Корень проверяется при построении плана; его существование и файлы — после выполнения проекта. Маски include/exclude появились в версии 0.3.0 и сохраняют прежние правила.

```json
{
  "schemaVersion": 2,
  "name": "MyLibrary",
  "versionSource": "Version.json",
  "projects": {
    "managed": {
      "adapter": "dotnet",
      "project": "Sources/MyLibrary/MyLibrary.csproj",
      "operation": "build",
      "configuration": "Release"
    }
  },
  "contents": [
    {
      "project": "managed",
      "include": ["**/*.dll"],
      "exclude": ["**/*Tests.dll"],
      "destination": "lib/net8.0",
      "preserveHierarchy": true
    }
  ],
  "deliveries": { "NuGet": "Delivery/NuGet/Delivery.json" }
}
```

В этом примере выбираются DLL из output и его подпапок. Для дерева output/Core/A.dll и output/Extensions/B.dll результатом будут lib/net8.0/Core/A.dll и lib/net8.0/Extensions/B.dll. При preserveHierarchy=false в lib/net8.0 окажутся A.dll и B.dll без подпапок.

| Поле | Правило |
|---|---|
| root, path | Выбирают корень адаптера и конкретный файл или каталог внутри него. Значения по умолчанию: output и точка. |
| source | Альтернатива project/root/path: существующий каталог относительно корня репозитория. |
| include | Непустой массив масок или точных путей. Без поля выбираются все файлы дерева, как при `**/*`. |
| exclude | Массив исключающих масок; применяется после include. Можно указать пустой массив. |
| preserveHierarchy | Булево значение, по умолчанию true. Сохраняет путь относительно выбранного каталога; false оставляет только имя файла. |
| rename | Объект, в котором ключ — точный путь выбранного файла относительно исходного каталога, а значение — новое имя файла без каталогов. |

Маски применяются только к каталогам и считаются относительно выбранного root/path. Звёздочка * не пересекает разделитель пути. ** занимает отдельный сегмент и соответствует нулю или более уровням: **/*.dll выбирает DLL как в самом корне, так и глубже; Core/**/*.dll — только под Core. Обычные символы трактуются буквально; ?, классы [] и абсолютные пути не поддерживаются. Разделители / и обратная косая черта равнозначны, сравнение не учитывает регистр Windows. Сегменты . и .. в масках запрещены. Пустые каталоги не копируются.

Пересекающиеся include не дублируют один файл. Если итоговый отбор пуст или разные файлы попадают в один путь назначения (в том числе при preserveHierarchy=false), выпуск завершается ошибкой. Иерархия считается от выбранного каталога, а не от положения ** в маске. Например, path=Core убирает префикс Core из копируемых относительных путей.

Для конкретного результата проекта используйте path без масок. При переименовании такого файла ключом rename служит его имя. Начиная с версии 0.5.0 rename всегда является объектом и работает совместно с include/exclude для обоих источников. При preserveHierarchy=true меняется только имя файла, его относительный каталог сохраняется. При false все выбранные файлы помещаются непосредственно в destination. Ключи rename нормализуются по разделителям и регистру Windows; повторы, маски в ключах, пути вместо новых имён и переименования невыбранных файлов приводят к ошибке.

Для готовых файлов укажите source. Например, одна запись заменяет отдельные записи LICENSE и README у Diagnostic:

```json
{
  "source": ".",
  "include": ["LICENSE", "Packages/Build/NuGet/README.md"],
  "destination": ".",
  "preserveHierarchy": false,
  "rename": { "LICENSE": "LICENSE.txt" },
  "deliveries": ["NuGet"]
}
```

В пакет попадут LICENSE.txt и README.md. Отбор, исключения, сохранение дерева и обнаружение конфликтов для source работают так же, как для результатов проекта. source нельзя сочетать с project, root или path. source всегда задаёт каталог; для единственного готового файла используйте include с его относительным путём. Для точных включений сборщик проверяет указанные файлы напрямую, без рекурсивного обхода всего репозитория. Только выбранные проекты запускаются: пакет с projects={} и записями source не требует сборки проектов.

Старое поле contents.file удалено и отклоняется как неизвестное. Для миграции преобразуйте старый путь относительно каталога пакета в include относительно source; в destination оставьте каталог назначения, а новое имя задайте через rename. Для перехода с именованных артефактов перенесите root/path в contents и удалите artifacts/artifact.

Проверка Tests/Integration/Packages/PackageContents.Tests.ps1 создаёт настоящий NuGet и проверяет его состав, отсутствие лишних файлов, сохранение дерева, уплощение и ошибки контракта. Параметр PackageToolsPackage запускает тот же тест установленным инструментом из nupkg.

## Собственные выпуски UDK

```powershell
& ./Packages/Build/Build.ps1 -PackagePath Packages/Windows/PackageTools/Package.json
```

PackageTools использует files-адаптер и собственный Version.json. Все остальные пакеты UDK выпускаются тем же PackageTools. Адаптер udk-native сохраняет ABI, MSBuild-интеграцию и вычисление native-зависимостей из реестра компонентов. OpenGLESRenderer включает ANGLE, публичные заголовки в include/ANGLE и лицензии. Зависимости компонентных nuspec не ограничены группой native, поэтому NuGet восстанавливает транзитивные пакеты и для смешанных net8.0 SDK.

Продуктовые Package.json UDK выбирают результаты напрямую в contents, без промежуточных artifacts: root=output для подготовленного дерева и root=build, path=Release, include=["XamlCompiler.exe"] для компилятора. Там, где нужен весь результат, include/exclude опускаются: сохраняется полное дерево. Параметры доставки и зависимости пакетов от этого упрощения не меняются.

У Previewer независимы Version.json продукта, PackageReference инструмента в Packages/Build.csproj и версии трёх UDK-зависимостей в Delivery.json PluginSDK. Тег и коммит репозитория Previewer определяют его выпуск. Native-библиотеки остаются в собственных NuGet-пакетах.

## Артефакты и проверки

Все проекты используют !artifacts/package-build/<пакет>/<имя-проекта> с output, build, install, dependencies или packages. Поэтому одинаковые локальные имена в разных пакетах не пересекаются. Путь одинаково формируется для локальных проектов и проектов внешнего реестра и не зависит от доставки. Адаптеры получают общий WorkDirectory; buildDirectory в описаниях проектов не поддерживается. Выпуски находятся в !artifacts/packages/nuget/<имя-пакета>, staging — staging/payload. Блокировки проектов удерживаются до завершения staging. NuGet.exe хранится в !tools собираемого репозитория; загрузка проверяется по закреплённому SHA-256.

Tests/Integration/Packages/PackageComposition.Tests.ps1 проверяет смешанный пакет, внешний корень, ошибки контрактов, восстановление NuGet-зависимости и конфликтующие файлы. Параметр PackageToolsPackage запускает тот же сценарий установленным инструментом из настоящего nupkg. Проверки конкретного PluginSDK принадлежат репозиторию Previewer.

## Несколько доставок и предварительные выпуски

contents может содержать deliveries: ["NuGet"] или ["Android"]. Сборщик выбирает только результаты выбранной доставки и необходимые проекты. Общие элементы без фильтра включаются всегда. releaseDependencies содержит package (путь к Package.json относительно текущего пакета), delivery и необязательный when (список доставок текущего пакета). Эти пакеты выпускаются первыми; циклы отвергаются при построении плана. Для NuGet зависимости копируются в feed корневого пакета, для Maven используется общий выходной репозиторий. Это порядок выпуска; зависимости потребителя описываются отдельно в Delivery.json либо исходном Gradle-проекте.

versionSource может быть строкой с JSON-путём либо объектом path/format/property. format=properties позволяет читать packageVersion из gradle.properties. Значение версии не изменяется при выпуске.

| Проект | Назначение |
|---|---|
| cmake-build | sourceDirectory, generator, configurations; корень build, без install |
| udk-native | component, generator; корень output с native NuGet payload |
| udk-prefab | component, toolchain, configuration, abis, apiLevel; корень output с вариантами Prefab |
| gradle-publish | projectDirectory, toolchain, tasks, refreshDependencies; корень output с Maven-публикацией |

Специализированные udk-native и udk-prefab требуют реестр компонентов и инфраструктуру исходного UDK; обычный сторонний репозиторий использует dotnet, cmake-install, cmake-build, files и nuget-restore. gradle-publish получает путь к resolver toolchain явно из JSON. Delivery adapter=maven-prefab формирует native AAR/POM, maven-repository переносит штатную Gradle-публикацию вместе с метаданными и контрольными суммами. NuGet dependencySource=udk-component вычисляет точные зависимости из компонентного реестра; обычные пакеты задают dependencies явно.

В UDK основной точкой запуска служит ./Packages/Build/Build.ps1. Параметр -All автоматически выбирает все Package.json и их доставки, -Delivery ограничивает способ доставки, а -PackagePath выбирает конкретный пакет. Оболочка использует исходный PackageTools, поэтому инструмент может выпускать сам себя без предварительной установки. Проверка -All -Plan не запускает сборку. Служебный MSBuild-проект из примера подключения предназначен для сторонних репозиториев; в самом UDK отдельный Build.csproj не нужен. PackageTools.Migration.Tests.ps1 сверяет все планы, а с BaselineDirectory сравнивает состав файлов и NuGet-зависимости с контрольными пакетами; CheckMaven проверяет Android-публикации.