# Универсальный инструмент выпуска пакетов

**Навигация:** [Документация](README.md) → Выпуск пакетов

PackageTools входит в поставку [UdkCli](UdkCli.md). Для работы из стороннего репозитория нужны `udk.exe`, его каталог `Tools` и Windows PowerShell 5.1.

## Запуск из другого репозитория

Из корня репозитория:

```powershell
udk package plan Packages/MyLibrary/Package.xml
udk package build Packages/MyLibrary/Package.xml
```

Первая команда проверяет план выпуска без сборки, вторая собирает пакет локально. Для дополнительных параметров можно вызвать `Tools/PackageTools/Build.ps1` из поставки напрямую. Отправку пакетов в feed выполняет отдельный шаг CI.

## Контракт проектов

Поле projects в Package.xml допускает два варианта. Основной — объект локальных определений: ключ задаёт имя проекта, значение содержит adapter и параметры адаптера. name и schemaVersion внутри локального проекта не указываются. Необязательные dependencies ссылаются на другие ключи того же объекта. Для общих проектов сохранён прежний вариант: строка с путём реестра Projects/Build.xml версии 1, который перечисляет отдельные файлы через includes; внешние проекты сохраняют явные schemaVersion=1 и name. Сборщик выполняет выбранные проекты и их зависимости в топологическом порядке; циклы и неизвестные зависимости отвергаются.

Пути внутри проекта относительны к корню собираемого репозитория. Адаптер предоставляет именованные корни результатов, например output, build или install. Состав пакета выбирает файл или каталог непосредственно через root/path в contents. Поля projects.<имя>.artifacts и contents.artifact удалены из контракта и отклоняются как неизвестные поля, включая проекты внешнего реестра.

| Адаптер | Параметры и корни результатов |
|---|---|
| dotnet | project (.csproj), operation (build/publish), configuration (Debug/Release), необязательные runtime и selfContained. Корень output. selfContained требует publish с runtime. |
| cmake-install | sourceDirectory, generator, architecture, configurations, parallel, variables. Корень install; CMAKE_INSTALL_PREFIX задаёт адаптер. |
| component-sources | component (XML со списками headers/sources), sourceRoot, includeRoot, publicHeaders, headerDestination, sourceDestination, manifestDestination. Корень output. |
| files | mappings с source и destination. Директория переносится содержимым; у файла destination задаёт полный путь. Корень output. |
| nuget-restore | id, точная version, необязательный массив sources. Корень package содержит восстановленный пакет. Глобальный PackageSources имеет приоритет над sources. |

component-sources берёт только явно перечисленные headers/sources; platformSources пока отвергается. publicHeaders выбирает публичные заголовки относительно sourceRoot; * и ? не пересекают /. Остальные заголовки размещаются рядом с реализацией. Этот адаптер не требует C++ генератора UDK.

cmake-install допускает preparation для нестандартной подготовки зависимости: script, parameters и properties. Hook получает RepositoryPath, WorkDirectory, Configurations, Generator и дополнительные parameters; возвращает hashtable объявленных properties с существующими каталогами. Свойства передаются CMake и становятся корнями результатов. Их можно передать через Properties напрямую. Подготовка ANGLE остаётся специализированным hook существующего пакета OpenGLESRenderer, а не частью ядра инструмента.

Для нового адаптера согласованно расширяются reader Private/Contract.ps1, диспетчеризация Build.ps1 и реализация Adapters. Обычный новый пакет не требует нового адаптера.

## Контракт пакета

Package.xml версии 2 содержит name, projects, непустой contents и deliveries с именованными способами доставки. Поле `version` обязательно. Оно принимает номер версии или ссылку из корневого `JsonReferences.json`. Пути deliveries относительны к каталогу пакета. contents.source относителен корню репозитория. Для пакета только из готовых файлов projects может быть пустым объектом. Если projects — строка, путь внешнего реестра относителен каталогу пакета; пути внутри любых определений проектов по-прежнему относительны корню репозитория.

```xml
<Package schemaVersion="2" name="MyLibrary" version="1.0.0">
  <Projects>
    <Project id="managed" adapter="dotnet" project="MyLibrary/MyLibrary.csproj" operation="build" configuration="Release" />
  </Projects>
  <Contents>
    <Content project="managed" root="output" path="MyLibrary.dll" destination="lib/net8.0" />
    <Content source="." destination=".">
      <Includes><Include>LICENSE</Include></Includes>
      <Rename><File from="LICENSE">LICENSE.txt</File></Rename>
    </Content>
  </Contents>
  <Deliveries>
    <Delivery name="NuGet">Delivery/NuGet/Delivery.xml</Delivery>
  </Deliveries>
</Package>
```

destination всегда задаёт каталог внутри payload, точка означает его корень. Каталог копируется содержимым с сохранением относительной иерархии по умолчанию; файловый результат проекта сохраняет имя. rename позволяет изменить имена файлов. Выход путей за границы корня, конфликты имён, отсутствующие результаты и пустой отбор приводят к ошибке.

Delivery.xml версии 1 выбирает adapter=nuget, id, supportedPlatforms=["Windows"], nuspec и необязательный noWarn. Необязательный dependencies содержит элементы id/version с точной версией без диапазона. Nuspec должен содержать {{DEPENDENCIES}}; адаптер заменяет его на dependency с точным диапазоном [version]. Повторы, ссылка на сам пакет и несовпадение placeholder с описанием отвергаются. Адаптер проверяет ID nuspec, подставляет {{VERSION}} и упаковывает готовый payload. Стандартная запись files в nuspec: payload\**\* → корень пакета.

В Package.xml версии 2 параметр `-Delivery` выбирает доставку по имени. Без параметра используется `defaultDelivery` или единственная объявленная доставка. При нескольких доставках без `defaultDelivery` нужно явно передать `-Delivery`. Нативная интеграция ищет единственную доставку с адаптером `nuget` и настройками `integration`, включая путь к `.targets`. Версия контракта Delivery.xml — 1.

## Отбор файлов в contents

В описаниях пакетов сначала перечисляются все записи contents с project, затем записи с source. Порядок внутри каждой группы сохраняется.

В PackageTools 0.4.0 отбор выполняется только напрямую в contents: root по умолчанию равен output, path — точке. Для CMake укажите root=build или root=install, для nuget-restore — root=package. Корень проверяется при построении плана; его существование и файлы — после выполнения проекта. Маски include/exclude появились в версии 0.3.0 и сохраняют прежние правила.

```xml
<Package schemaVersion="2" name="MyLibrary" version="1.0.0">
  <Projects>
    <Project id="managed" adapter="dotnet" project="Sources/MyLibrary/MyLibrary.csproj" operation="build" configuration="Release" />
  </Projects>
  <Contents>
    <Content project="managed" destination="lib/net8.0" preserveHierarchy="true">
      <Includes><Include>**/*.dll</Include></Includes>
      <Excludes><Exclude>**/*Tests.dll</Exclude></Excludes>
    </Content>
  </Contents>
  <Deliveries>
    <Delivery name="NuGet">Delivery/NuGet/Delivery.xml</Delivery>
  </Deliveries>
</Package>
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

```xml
<Package schemaVersion="2" name="MyLibrary" version="1.0.0">
  <Projects>
    <Project id="managed" adapter="dotnet" project="Sources/MyLibrary/MyLibrary.csproj" operation="build" configuration="Release" />
  </Projects>
  <Contents>
    <Content project="managed" destination="lib/net8.0" preserveHierarchy="true">
      <Includes><Include>**/*.dll</Include></Includes>
      <Excludes><Exclude>**/*Tests.dll</Exclude></Excludes>
    </Content>
  </Contents>
  <Deliveries>
    <Delivery name="NuGet">Delivery/NuGet/Delivery.xml</Delivery>
  </Deliveries>
</Package>
```

В пакет попадут LICENSE.txt и README.md. Отбор, исключения, сохранение дерева и обнаружение конфликтов для source работают так же, как для результатов проекта. source нельзя сочетать с project, root или path. source всегда задаёт каталог; для единственного готового файла используйте include с его относительным путём. Для точных включений сборщик проверяет указанные файлы напрямую, без рекурсивного обхода всего репозитория. Только выбранные проекты запускаются: пакет с projects={} и записями source не требует сборки проектов.

Старое поле contents.file удалено и отклоняется как неизвестное. Для миграции преобразуйте старый путь относительно каталога пакета в include относительно source; в destination оставьте каталог назначения, а новое имя задайте через rename. Для перехода с именованных артефактов перенесите root/path в contents и удалите artifacts/artifact.

Проверка Tests/Integration/Packages/PackageContents.Tests.ps1 создаёт настоящий NuGet и проверяет его состав, отсутствие лишних файлов, сохранение дерева, уплощение и ошибки контракта. Параметр `UdkCliDirectory` запускает ту же проверку скриптами из поставки UdkCli.

## Собственные выпуски UDK

```powershell
& ./Packages/Build/Build.ps1 -PackagePath Packages/Windows/XamlCompiler/Package.xml
```

Продуктовые пакеты UDK выпускаются через PackageTools. Адаптер udk-native сохраняет ABI, MSBuild-интеграцию и вычисление native-зависимостей из реестра компонентов. OpenGLESRenderer включает ANGLE, публичные заголовки в include/ANGLE и лицензии. Зависимости компонентных nuspec не ограничены группой native, поэтому NuGet восстанавливает транзитивные пакеты и для смешанных net8.0 SDK.

Продуктовые Package.xml UDK выбирают результаты напрямую в contents, без промежуточных artifacts: root=output для подготовленного дерева и root=build, path=Release, include=["XamlCompiler.exe"] для компилятора. Там, где нужен весь результат, include/exclude опускаются: сохраняется полное дерево. Параметры доставки и зависимости пакетов от этого упрощения не меняются.

У Previewer независимы Version.json продукта, PackageReference инструмента в Packages/Build.csproj и версии трёх UDK-зависимостей в Delivery.xml PluginSDK. Тег и коммит репозитория Previewer определяют его выпуск. Native-библиотеки остаются в собственных NuGet-пакетах.

## Артефакты и проверки

Все проекты используют !artifacts/package-build/<пакет>/<имя-проекта> с output, build, install, dependencies или packages. Поэтому одинаковые локальные имена в разных пакетах не пересекаются. Путь одинаково формируется для локальных проектов и проектов внешнего реестра и не зависит от доставки. Адаптеры получают общий WorkDirectory; buildDirectory в описаниях проектов не поддерживается. Выпуски находятся в !artifacts/packages/nuget/<имя-пакета>, staging — staging/payload. Блокировки проектов удерживаются до завершения staging. NuGet.exe хранится в !tools собираемого репозитория; загрузка проверяется по закреплённому SHA-256.

Tests/Integration/Packages/PackageComposition.Tests.ps1 проверяет смешанный пакет, внешний корень, ошибки контрактов, восстановление NuGet-зависимости и конфликтующие файлы. Параметр `UdkCliDirectory` запускает ту же проверку скриптами из поставки UdkCli. Проверки конкретного PluginSDK принадлежат репозиторию Previewer.

## Несколько доставок и предварительные выпуски

contents может содержать deliveries: ["NuGet"] или ["Android"]. Сборщик выбирает только результаты выбранной доставки и необходимые проекты. Общие элементы без фильтра включаются всегда. releaseDependencies содержит package (путь к Package.xml относительно текущего пакета), delivery и необязательный when (список доставок текущего пакета). Эти пакеты выпускаются первыми; циклы отвергаются при построении плана. Для NuGet зависимости копируются в feed корневого пакета, для Maven используется общий выходной репозиторий. Это порядок выпуска; зависимости потребителя описываются отдельно в Delivery.xml либо исходном Gradle-проекте.

Ссылки вида `${UDK_VERSION.version}` разрешаются по [карте JSON-ссылок](Components.md#ссылки-на-json). Значение версии не изменяется при выпуске.

| Проект | Назначение |
|---|---|
| cmake-build | sourceDirectory, generator, configurations; корень build, без install |
| udk-native | component, cmakeGeneratorWindows (имя генератора CMake для Windows); корень output с native NuGet payload |
| udk-dotnet | component, необязательные projectId, operation (build по умолчанию или publish), configuration (Release по умолчанию или Debug), runtime и selfContained. Корень output. Путь к сгенерированному .csproj определяется по правилам ProjectTools. Если C#-проектов несколько, укажите projectId. |
| udk-component-sources | Параметры component-sources, где component задаёт имя нативного компонента в Components.xml. Список файлов разрешается по описанию компонента и записывается в manifestDestination. |
| udk-prefab | component, toolchain, configuration, abis, apiLevel; корень output с вариантами Prefab |
| gradle-publish | projectDirectory, toolchain, tasks, refreshDependencies; корень output с Maven-публикацией |

Специализированные udk-native и udk-prefab требуют реестр компонентов и инфраструктуру исходного UDK; обычный сторонний репозиторий использует dotnet, cmake-install, cmake-build, files и nuget-restore. gradle-publish получает путь к resolver toolchain явно из XML. Delivery adapter=maven-prefab формирует native AAR/POM, maven-repository переносит штатную Gradle-публикацию вместе с метаданными и контрольными суммами. NuGet dependencySource=udk-component вычисляет точные зависимости из компонентного реестра; обычные пакеты задают dependencies явно.

В UDK основной точкой запуска служит ./Packages/Build/Build.ps1. Параметр -All автоматически выбирает все Package.xml и их доставки, -Delivery ограничивает способ доставки, а -PackagePath выбирает конкретный пакет. Оболочка использует исходный PackageTools. Проверка -All -Plan не запускает сборку. PackageTools.Migration.Tests.ps1 сверяет все планы, а с BaselineDirectory сравнивает состав файлов и NuGet-зависимости с контрольными пакетами; CheckMaven проверяет Android-публикации.