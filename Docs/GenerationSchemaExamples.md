# Схема генерации UDK

Четыре примера показывают синтаксис схемы 8 для реестра и трёх зарегистрированных компонентов. Фрагменты опускают настройки сборки, которые не участвуют в примерах. В `Components.xml` репозитория приведён полный рабочий реестр.

В `Files` можно объявить записи напрямую или объединить их в `Group`:

| Элемент | Назначение |
|---|---|
| `File` | Выбирает существующие файлы для отображения. |
| `Input role="…"` | Выбирает существующие файлы для указанной входной роли скрипта. Эти файлы также доступны фильтрам. |
| `Output role="…"` | Задаёт шаблон пути для запланированного выхода. Если выход объявлен в группе, его экземпляр в этой области входит в неё. |
| `Ref tag="…" id="…"` | Подставляет указанный элемент целиком, включая его атрибуты и содержимое. |

Настройки сборщиков в проекте объявляются в `<Extension buildSystem="MSBuild">` или `<Extension buildSystem="CMake">`. Вложенный `Files` использует те же объявления файлов и групп. Роли `msbuild-props`, `msbuild-targets` и `cmake` допустимы только в расширении соответствующего сборщика. Общие исходники, заголовки и выходы остаются в `Project/Files`. Группы из расширений доступны фильтрам того же проекта. Реестр может объявить общее расширение MSBuild для импортов `msbuild-props` с `projectType="native"`.

`Files.Input` сокращает `Files → Input`, а `ConsumerIntegration.Files.Input` сокращает `ConsumerIntegration → Files → Input` внутри расширения сборщика. Атрибуты сокращённого тега относятся к `Input`. Для ссылок на объявления корневого реестра используется префикс `ROOT-` в `id` объявления и в `Ref`.

## 1. Реестр и общие файлы

```xml
<ComponentRegistry schemaVersion="8">
  <Components>
    <Component>Projects/Components/Library/Diagnostic.xml</Component>
    <Component>Projects/Components/Library/Helpers.xml</Component>
    <Component>Projects/Components/Application/UdkCli.xml</Component>
  </Components>

  <Generation>
    <Settings buildSystem="MSBuild">
      <SolutionName>UniversalDevKit</SolutionName>
      <ProjectDirectory>
        <Default>Projects/!Generated/MsBuild/{kind:title}/{name}</Default>
      </ProjectDirectory>
    </Settings>
  </Generation>

  <Extension buildSystem="MSBuild">
    <Files>
      <Input role="msbuild-props" projectType="native">Projects/MsBuild/BuildLayout.props</Input>
      <Output role="dependencies-props"
              id="ROOT-DependenciesProps">{projectDirectory}/{solutionName}.{name}.Dependencies.{ext}</Output>
    </Files>
  </Extension>

  <Files>
    <Group id="ROOT-Version">
      <Input role="version-source">Version.json</Input>
      <Output role="version-header">Projects/!Generated/Includes/UniversalDevKit/Version.{ext}</Output>
      <Output role="version-props">Projects/!Generated/MsBuild/{solutionName}.Version.{ext}</Output>
    </Group>

    <Output role="sourceIntegration-targets"
            id="ROOT-SourcesIntegration">Projects/!Generated/MsBuild/{solutionName}.Sources.{ext}</Output>
    <Output role="component-exportHeader">Projects/!Generated/Includes/UniversalDevKit/{name}/Export.{ext}</Output>
    <Output role="project-nativeApplication">{projectDirectory}/{name}.{ext}</Output>
    <Output role="project-nativeLibrary">{projectDirectory}/{solutionName}.{name}.{variant:title}.{ext}</Output>
    <Output role="project-classLibrary">{projectDirectory}/{name}.{framework}.{ext}</Output>
    <Output role="project-headerCheck">{projectDirectory}/{solutionName}.{name}.HeaderCheck.{ext}</Output>
    <Output role="shared-items">{projectDirectory}/{solutionName}.{name}.Shared.{ext}</Output>
    <Output role="source-headerCheck">{projectDirectory}/HeaderCheck.{ext}</Output>
    <Output role="core-exportHeader">Projects/!Generated/Includes/UniversalDevKit/Export.{ext}</Output>
  </Files>

  <Filters>
    <Filter filter="{Tree:Solution}/Version">
      <Ref tag="Group" id="ROOT-Version" />
    </Filter>
  </Filters>
</ComponentRegistry>
```

Скрипт открывает зарегистрированные манифесты и обновляет `UniversalDevKit.sln`. Вход `version-source` выбирает ровно один JSON. Из него скрипт формирует `Version.g.h` и `UniversalDevKit.Version.g.props`. Исходный JSON и оба запланированных выхода попадают в папку решения `Version` через одну группу.

`BuildLayout.props` уже есть в репозитории. Входная роль `msbuild-props` подключает его через импорт, а `projectType="native"` ограничивает импорт нативными проектами. `sourceIntegration-targets` создаётся один раз на реестр из графа зарегистрированных компонентов. Проектные шаблоны из реестра раскрываются в контексте соответствующих проектов.

## 2. Diagnostic и локальное имя проекта

```xml
<Component name="Diagnostic">
  <Projects>
    <Project id="native" kind="library" projectType="native" stateScope="process">
      <Files>
        <Group id="Sources">
          <Input role="header">Includes/Diagnostic/UniversalDevKit/Diagnostic/**/*.h</Input>
          <Input role="source">Sources/Diagnostic/Native/**/*.cpp</Input>
        </Group>

      </Files>


      <Filters>
        <Filter filter="{Tree:Project}/Sources">
          <Ref tag="Group" id="Sources" />
        </Filter>
      </Filters>
      <Extension buildSystem="MSBuild">
        <Files.Input id="NativeBuild" role="msbuild-targets">Sources/Diagnostic/Native/Spdlog.targets</Files.Input>
        <Filters>
          <Filter filter="{Tree:Project}/Build">
            <Ref tag="Input" id="NativeBuild" />
            <Ref tag="Output" id="ROOT-DependenciesProps" />
          </Filter>
        </Filters>
      </Extension>
    </Project>

    <Project id="dotnet" kind="library" projectType="classLibrary">
      <Files>
        <Input role="source">Sources/Diagnostic/DotNet/**/*.cs</Input>
        <Output role="project-classLibrary">{projectDirectory}/{solutionName}.{name}.Net8.{ext}</Output>
      </Files>


      <RuntimeDependencies>
        <Dependency projectId="native" variant="Dynamic" />
      </RuntimeDependencies>
      <Extension buildSystem="MSBuild">
        <Properties>
          <TargetFramework>net8.0</TargetFramework>
        </Properties>
      </Extension>
    </Project>
  </Projects>
</Component>
```

Нативный проект получает только вариант `Dynamic` из-за `stateScope="process"`. Если проект поддерживает оба варианта, их можно задать как `<Variants>static;dynamic</Variants>`. Тогда общий шаблон `project-nativeLibrary` раскроется дважды, а `dependencies-props` останется одним выходом на библиотеку.

Фильтр `Build` показывает `Spdlog.targets` из расширения и напрямую ссылается на запланированный `UniversalDevKit.Diagnostic.Dependencies.g.props`. `Ref` подставляет объявление `Output` с `id="ROOT-DependenciesProps"`. Его роль вычисляется для текущего нативного проекта. Импорт созданного `.props` скрипт строит по тому же пути из плана.

Локальный `project-classLibrary` даёт `UniversalDevKit.Diagnostic.Net8.csproj`. Связь с нативной библиотекой сохраняется через `projectId` и `variant`, поэтому имена файлов проектов можно менять независимо.

## 3. Helpers и два связанных выхода HeaderCheck

```xml
<Component name="Helpers">
  <Projects>
    <Project id="native" kind="library" projectType="native" libraryType="headerOnly">
      <Files>
        <Input role="header">Includes/Helpers/UniversalDevKit/Helpers/**/*.h</Input>

        <Group id="HeaderCheck">
          <Output role="source-headerCheck">{projectDirectory}/Checks/PublicHeaders.{ext}</Output>
        </Group>
      </Files>

      <Filters>
        <Filter filter="{Tree:Solution}/Checks">
          <Ref tag="Group" id="HeaderCheck" />
        </Filter>
      </Filters>
    </Project>
  </Projects>
</Component>
```

Для `headerOnly` скрипт планирует проверочный проект и исходник, который включает публичные заголовки. Путь `UniversalDevKit.Helpers.HeaderCheck.vcxproj` берётся из реестра. Локальный шаблон меняет путь исходника на `Checks/PublicHeaders.g.cpp` относительно каталога проекта. Скрипт строит ссылку внутри `.vcxproj` по фактическому пути исходника.

Исходник уже входит в группу `HeaderCheck` через объявление `Output`. Фильтр показывает его в папке решения `Checks`. Сопутствующий файл проекта получает путь `UniversalDevKit.Helpers.HeaderCheck.vcxproj.filters`.

## 4. UdkCli и ссылка на общий выход

```xml
<Component name="UdkCli">
  <Files>
    <Group id="Tools">
      <File>Sources/Windows/UdkCli/Tools/**/*</File>
    </Group>

    <Group id="Integration">
      <Ref tag="Output" id="ROOT-SourcesIntegration" />
    </Group>
  </Files>

  <Filters>
    <Filter filter="{Tree:Solution}/UdkCli/Tools" preserveTree="true">
      <Ref tag="Group" id="Tools" />
    </Filter>
    <Filter filter="{Tree:Solution}/UdkCli/Integration">
      <Ref tag="Group" id="Integration" />
    </Filter>
  </Filters>

  <Projects>
    <Project id="native" kind="application" projectType="native">
      <Files>
        <Input role="header">Sources/Windows/UdkCli/**/*.h</Input>
        <Input role="source">Sources/Windows/UdkCli/**/*.cpp</Input>
      </Files>
      <Extension buildSystem="MSBuild">
        <Files>
          <Input role="msbuild-props">Sources/Windows/UdkCli/UdkCli.props</Input>
        </Files>
      </Extension>
    </Project>
  </Projects>
</Component>
```

Группа `Tools` показывает существующие файлы с сохранением дерева каталогов. Группа `Integration` показывает общий `UniversalDevKit.Sources.g.targets`. Ссылка находит объявление `ROOT-SourcesIntegration` в реестре, а роль `sourceIntegration-targets` даёт один экземпляр на весь реестр. У входа `msbuild-props` внутри проекта область импорта уже задана родительским `Project`.

Для приложения скрипт применяет `project-nativeApplication` и `shared-items`. Получаются `UdkCli.vcxproj` и `UniversalDevKit.UdkCli.Shared.vcxitems` со своими `.filters`.

## Как раскрывается Ref

Парсер ищет объявление по паре `tag` и `id` и берёт первое совпадение:

| Где объявлен `Ref` | Порядок поиска |
|---|---|
| Внутри проекта | Текущий проект → его компонент → реестр |
| Внутри компонента вне проекта | Текущий компонент → реестр |
| Внутри реестра | Реестр |

`Files`, `Group` и `Filters` используют область родительского проекта, компонента или реестра. Два объявления с одинаковой парой `tag` и `id` в одной области дают ошибку. Соседние проекты и компоненты вне области поиска.

Внутри фильтра `Diagnostic` запись `<Ref tag="Group" id="Sources" />` раскрывается вместе с внешним тегом `Group`:

```xml
<Group id="Sources">
  <Input role="header">Includes/Diagnostic/UniversalDevKit/Diagnostic/**/*.h</Input>
  <Input role="source">Sources/Diagnostic/Native/**/*.cpp</Input>
</Group>
```

Точно так же `<Ref tag="Output" id="ROOT-DependenciesProps" />` раскрывается в элемент `Output` со всеми атрибутами и шаблоном пути:

```xml
<Output role="dependencies-props"
        id="ROOT-DependenciesProps">{projectDirectory}/{solutionName}.{name}.Dependencies.{ext}</Output>
```

В этом примере парсер находит `Output id="ROOT-DependenciesProps"` в реестре. Роль `dependencies-props` относится к проекту, поэтому шаблон вычисляется в контексте нативного проекта `Diagnostic`. Подстановки `{projectDirectory}`, `{solutionName}`, `{name}` и `{ext}` дают путь `Projects/!Generated/MsBuild/Library/Diagnostic/UniversalDevKit.Diagnostic.Dependencies.g.props`. Для сравнения, роль `sourceIntegration-targets` из примера `UdkCli` вычисляется один раз в контексте реестра.

Вложенный `Ref` ищется из области, где он был объявлен. Если проект ссылается на группу реестра, а внутри неё есть `<Ref tag="Output" id="ROOT-DependenciesProps" />`, вложенная ссылка ищет объявление в реестре. Шаблон найденного проектного выхода при этом вычисляется для проекта, который использует группу.

После раскрытия парсер обрабатывает элемент по правилам места, где стояла ссылка. Внутри `Filter` группа даёт файлы для отображения. Внутри `Files/Group` подставленный `Output` включает запланированный файл в выборку. Повторное использование элемента сохраняет связь с исходным объявлением, поэтому ссылки на одну группу или выход используют те же входы и выходы плана. Парсер сообщает об отсутствующей цели или цикле ссылок.

## Наследование и вычисление путей

- Скрипт определяет состав выходов по типу и настройкам проекта. `Output` задаёт путь для соответствующей роли. Например, объявление `source-headerCheck` в реестре используется при генерации HeaderCheck.
- Для проектной роли локальный `Output` переопределяет шаблон реестра. Если у локального объявления нет `id`, идентификатор наследуется. Например, при локальном переименовании файла роли `dependencies-props` ссылка `<Ref tag="Output" id="ROOT-DependenciesProps" />` получит путь из локального шаблона.
- `id` в `Output` служит идентификатором для ссылок. Подстановка `{name}` в пути означает имя компонента. Объявление без `id` можно использовать непосредственно в группе.
- Пути отсчитываются от корня реестра. Скрипт подставляет `{ext}` по роли, например `vcxproj`, `vcxitems`, `csproj`, `g.h`, `g.cpp`, `g.props` или `g.targets`. Путь сопутствующего `.filters` вычисляется добавлением суффикса к пути проекта.
- Перед записью скрипт вычисляет пути, проверяет коллизии и разрешает ссылки. По тем же путям он строит импорты, ссылки между проектами и содержимое фильтров. Если запланированный выход остался без шаблона, генерация останавливается до записи файлов.