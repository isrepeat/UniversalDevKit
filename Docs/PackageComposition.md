# Универсальный инструмент выпуска пакетов

**Навигация:** [Документация](README.md) → Выпуск пакетов

UDK выпускает UniversalDevKit.PackageTools как самостоятельный NuGet. Реализация находится в Sources/PackageTools; пакет содержит все адаптеры, helpers, manifest NuGet.exe и MSBuild targets. Использование инструмента не требует checkout UDK. AndroidAppPreviewer — отдельный репозиторий и самостоятельный владелец выпуска Previewer/PluginSDK.

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
    <PackageReference Include="UniversalDevKit.PackageTools" Version="0.2.0" PrivateAssets="all" />
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

Поле projects в Package.json допускает два варианта. Основной — объект локальных определений: ключ задаёт имя проекта, значение содержит adapter, artifacts и параметры адаптера. name и schemaVersion внутри локального проекта не указываются. Необязательные dependencies ссылаются на другие ключи того же объекта. Для общих проектов сохранён прежний вариант: строка с путём реестра Projects/Build.json версии 1, который перечисляет отдельные файлы через includes; внешние проекты сохраняют явные schemaVersion=1 и name. Сборщик выполняет выбранные проекты и их зависимости в топологическом порядке; циклы и неизвестные зависимости отвергаются.

Пути внутри проекта относительны к корню собираемого репозитория. Результат artifacts.<имя> содержит root и path: адаптер предоставляет именованный корень, а path выбирает существующий файл или каталог внутри него.

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

Package.json версии 2 содержит name, versionSource, projects, непустой contents и deliveries с именованными способами доставки. Пути versionSource, deliveries и contents.file относительны к каталогу пакета. Если projects — строка, путь внешнего реестра также относителен каталогу пакета; пути внутри любых определений проектов по-прежнему относительны корню репозитория.

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
      "configuration": "Release",
      "artifacts": { "assembly": { "root": "output", "path": "MyLibrary.dll" } }
    }
  },
  "contents": [
    { "project": "managed", "artifact": "assembly", "destination": "lib/net8.0" },
    { "file": "../../LICENSE", "destination": "LICENSE.txt" }
  ],
  "deliveries": { "NuGet": "Delivery/NuGet/Delivery.json" }
}
```

Для результата проекта destination — каталог payload; файловый результат сохраняет имя, rename позволяет его изменить. Каталог копируется содержимым. Для file значение destination — полный путь файла. Точка означает корень payload. Выход путей за границы корня, конфликты имён, отсутствующие результаты и пустые каталоги результатов приводят к ошибке.

Delivery.json версии 1 выбирает adapter=nuget, id, supportedPlatforms=["Windows"], nuspec и необязательный noWarn. Необязательный dependencies содержит элементы id/version с точной версией без диапазона. Nuspec должен содержать {{DEPENDENCIES}}; адаптер заменяет его на dependency с точным диапазоном [version]. Повторы, ссылка на сам пакет и несовпадение placeholder с описанием отвергаются. Адаптер проверяет ID nuspec, подставляет {{VERSION}} и упаковывает готовый payload. Стандартная запись files в nuspec: payload\**\* → корень пакета.

Все продуктовые Package.json UDK переведены на schemaVersion: 2. Старые упаковщики удалены. Версия Delivery.json остаётся 1: это отдельный контракт доставки, а не версия Package.json. Выбор выполняется параметром -Delivery; без него выбирается NuGet либо единственная доставка.

## Собственные выпуски UDK

```powershell
& ./Packages/Build/Build.ps1 -PackagePath Packages/Windows/PackageTools/Package.json
```

PackageTools использует files-адаптер и собственный Version.json. Все остальные пакеты UDK выпускаются тем же PackageTools. Адаптер udk-native сохраняет ABI, MSBuild-интеграцию и вычисление native-зависимостей из реестра компонентов. OpenGLESRenderer включает ANGLE, публичные заголовки в include/ANGLE и лицензии. Зависимости компонентных nuspec не ограничены группой native, поэтому NuGet восстанавливает транзитивные пакеты и для смешанных net8.0 SDK.

У Previewer независимы Version.json продукта, PackageReference инструмента в Packages/Build.csproj и версии трёх UDK-зависимостей в Delivery.json PluginSDK. Тег и коммит репозитория Previewer определяют его выпуск. Native-библиотеки остаются в собственных NuGet-пакетах.

## Артефакты и проверки

Локальные проекты используют !artifacts/projects/<windows|android>/udk/<пакет>/<локальное-имя> с output, build, install, dependencies или packages. Поэтому одинаковые локальные имена в разных пакетах не пересекаются. Проекты внешнего реестра сохраняют прежний путь !artifacts/projects/windows/udk/<имя>. Выпуски находятся в !artifacts/packages/nuget/<имя-пакета>, staging — staging/payload. Блокировки проектов удерживаются до завершения staging. NuGet.exe хранится в !tools собираемого репозитория; загрузка проверяется по закреплённому SHA-256.

Tests/Integration/Packages/PackageComposition.Tests.ps1 проверяет смешанный пакет, внешний корень, ошибки контрактов, восстановление NuGet-зависимости и конфликтующие файлы. Параметр PackageToolsPackage запускает тот же сценарий установленным инструментом из настоящего nupkg. Проверки конкретного PluginSDK принадлежат репозиторию Previewer.

## Несколько доставок и предварительные выпуски

contents может содержать deliveries: ["NuGet"] или ["Android"]. Сборщик выбирает только результаты выбранной доставки и необходимые проекты. Общие элементы без фильтра включаются всегда. releaseDependencies содержит package (путь к Package.json относительно текущего пакета), delivery и необязательный when (список доставок текущего пакета). Эти пакеты выпускаются первыми; циклы отвергаются при построении плана. Для NuGet зависимости копируются в feed корневого пакета, для Maven используется общий выходной репозиторий. Это порядок выпуска; зависимости потребителя описываются отдельно в Delivery.json либо исходном Gradle-проекте.

versionSource может быть строкой с JSON-путём либо объектом path/format/property. format=properties позволяет читать packageVersion из gradle.properties. Значение версии не изменяется при выпуске.

| Проект | Назначение |
|---|---|
| cmake-build | sourceDirectory, generator, configurations; корень build, без install |
| udk-native | component, generator, buildDirectory; корень output с native NuGet payload |
| udk-prefab | component, toolchain, configuration, abis, apiLevel; корень output с вариантами Prefab |
| gradle-publish | projectDirectory, toolchain, tasks, refreshDependencies; корень output с Maven-публикацией |

Специализированные udk-native и udk-prefab требуют реестр компонентов и инфраструктуру исходного UDK; обычный сторонний репозиторий использует dotnet, cmake-install, cmake-build, files и nuget-restore. gradle-publish получает путь к resolver toolchain явно из JSON. Delivery adapter=maven-prefab формирует native AAR/POM, maven-repository переносит штатную Gradle-публикацию вместе с метаданными и контрольными суммами. NuGet dependencySource=udk-component вычисляет точные зависимости из компонентного реестра; обычные пакеты задают dependencies явно.

В UDK можно вызвать ./Packages/Build/Build.ps1 -All или dotnet msbuild Packages/Build.csproj -t:PackRepository. Проект использует исходный PackageTools через UdkPackageToolsEntry, чтобы инструмент мог выпускать сам себя без предварительной установки. Проверка -All -Plan не запускает сборку. PackageTools.Migration.Tests.ps1 сверяет все планы, а с BaselineDirectory сравнивает состав файлов и NuGet-зависимости с контрольными пакетами; CheckMaven проверяет Android-публикации.