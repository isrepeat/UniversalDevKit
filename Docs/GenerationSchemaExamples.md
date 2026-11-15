# Предлагаемая схема генерации UDK

Примеры идут от одного файла до реестра с несколькими проектами. Имена компонентов и пути к шаблонам учебные. Новый синтаксис `Output` пока обсуждается. Фрагменты с ним нельзя передавать текущему ProjectTools.

## 1. Существующий файл в решении

Компонент может описывать файлы для просмотра, даже если его собирает внешний инструмент и у него нет блока `Projects`.

```xml
<Component name="MobileAssets">
  <Files>
    <Group name="Sources">
      <File>Sources/Android/MobileAssets/**/*</File>
    </Group>
  </Files>
  <Filters>
    <Filter filter="{Tree:Solution}/Sources/Android/MobileAssets"
            preserveTree="true">
      <GroupRef>Sources</GroupRef>
    </Filter>
  </Filters>
</Component>
```

`File` выбирает существующие файлы. `GroupRef` выбирает всю группу. `preserveTree="true"` сохраняет подкаталоги относительно фиксированной части маски. Эта форма уже поддерживается.

## 2. Один выход из шаблона

```xml
<Files>
  <Group name="PublicHeaders">
    <Output format="meta:header"
            template="Sources/Example/Config.h.in">Projects/!Generated/Includes/UniversalDevKit/{name}/Public.Config.{ext}</Output>
  </Group>
</Files>
<Filters>
  <Filter filter="{Tree:Solution}/Projects/!Generated/Includes/UniversalDevKit/{name}">
    <GroupRef>PublicHeaders</GroupRef>
  </Filter>
</Filters>
```

В контексте компонента `Example` путь раскрывается в `Projects/!Generated/Includes/UniversalDevKit/Example/Public.Config.g.h`. Формат задаёт `ext = g.h`. Шаблон пути явно содержит точку, каталог, префикс и базовое имя. Шаблон содержимого `Config.h.in` получает данные текущего контекста.

Тот же `Output` можно объявить в реестре, компоненте или проекте. На уровне реестра он вычисляется один раз с общими данными. На уровне компонента доступно его имя. На уровне проекта дополнительно доступны тип, категория и данные варианта, когда этот выход вычисляется для варианта. Если убрать фильтр, выход остаётся в плане генерации.

## 3. Один файл в двух деревьях

```xml
<Files>
  <Group name="BuildFiles">
    <File>Sources/Example/Build.cmake</File>
    <Output format="meta:props"
            generate="dependencies">Projects/!Generated/MsBuild/Library/{name}/{name}.Dependencies.{ext}</Output>
  </Group>
</Files>
<Filters>
  <Filter filter="{Tree:Project}/Build">
    <GroupRef>BuildFiles</GroupRef>
  </Filter>
  <Filter filter="{Tree:Solution}/Projects/!Generated/MsBuild/Library/{name}">
    <Match>**/*.g.props</Match>
  </Filter>
</Filters>
```

Этот фрагмент находится в нативном проекте библиотеки. В его папке `Build` видны оба файла. Фильтр решения выбирает только `.g.props` по вычисленному пути. Маска `Match` проверяет объявления из `Files` в той же области. Определение `File` даёт путь для просмотра. Для подключения CMake-правил к сборке используется существующее типизированное объявление `CMake`.

`generate="dependencies"` вызывает документированную операцию расчёта графа. Формат `meta:props` задаёт расширение `g.props`. Для одного выхода можно задать либо `template`, либо `generate`. У форматов проектов, например `project:shared`, есть встроенный способ формирования содержимого, поэтому оба атрибута можно опустить.

## 4. Общий реестр

Пример реестра для учебных компонентов из этого документа. Номер версии нового контракта определится при реализации.

```xml
<ComponentRegistry>
  <Components>
    <Component>Projects/Components/Library/MobileAssets.xml</Component>
    <Component>Projects/Components/Library/Headers.xml</Component>
    <Component>Projects/Components/Library/Telemetry.xml</Component>
  </Components>

  <Generation>
    <Integration>
      <VersionSource>Version.json</VersionSource>
    </Integration>
    <MSBuild>
      <Solution>UniversalDevKit.sln</Solution>
      <Configurations>Debug;Release</Configurations>
      <Platforms>x64</Platforms>
    </MSBuild>
  </Generation>

  <Files>
    <Group name="CommonHeaders">
      <Output format="meta:header"
              template="Templates/Export.h.in">Projects/!Generated/Includes/UniversalDevKit/Export.{ext}</Output>
      <Output format="meta:header"
              template="Templates/Version.h.in">Projects/!Generated/Includes/UniversalDevKit/Version.{ext}</Output>
    </Group>
    <Group name="CommonMSBuild">
      <Output format="meta:props"
              template="Templates/Version.props.in">Projects/!Generated/MsBuild/UniversalDevKit.Version.{ext}</Output>
      <Output format="meta:targets"
              generate="sourceIntegration">Projects/!Generated/MsBuild/UniversalDevKit.Sources.{ext}</Output>
    </Group>
  </Files>

  <Filters>
    <Filter filter="{Tree:Solution}/Projects/!Generated/Includes/UniversalDevKit">
      <GroupRef>CommonHeaders</GroupRef>
    </Filter>
    <Filter filter="{Tree:Solution}/Projects/!Generated/MsBuild">
      <GroupRef>CommonMSBuild</GroupRef>
    </Filter>
  </Filters>
</ComponentRegistry>
```

`VersionSource` даёт общие данные обоим шаблонам версии. `sourceIntegration` читает граф реестра. Путь каждого выходного файла указан один раз. Компонентный `Export.g.h` из следующего примера вычисляет свой путь самостоятельно.

## 5. Header-only библиотека и проверка заголовков

```xml
<Component name="Headers">
  <Projects>
    <Project id="native" kind="library" projectType="native" libraryType="headerOnly">
      <Files>
        <Group name="PublicHeaders">
          <Header>Includes/Headers/UniversalDevKit/Headers/**/*.h</Header>
          <Output format="meta:header"
                  template="Templates/ComponentExport.h.in">Projects/!Generated/Includes/UniversalDevKit/{name}/Export.{ext}</Output>
        </Group>
        <Group name="Projects">
          <Output format="project:shared">Projects/!Generated/MsBuild/Library/{name}/UniversalDevKit.{name}.Shared.{ext}</Output>
          <Output format="project:native"
                  generate="headerCheck">Projects/!Generated/MsBuild/Library/{name}/UniversalDevKit.{name}.HeaderCheck.{ext}</Output>
        </Group>
      </Files>
      <Filters>
        <Filter filter="{Tree:Project}/Headers">
          <GroupRef>PublicHeaders</GroupRef>
        </Filter>
        <Filter filter="{Tree:Solution}/Projects/!Generated/MsBuild/Library/{name}">
          <GroupRef>Projects</GroupRef>
        </Filter>
      </Filters>
    </Project>
  </Projects>
</Component>
```

Операция `headerCheck` строит проверочный проект и сопутствующий `HeaderCheck.g.cpp` из списка публичных заголовков. Путь сопутствующего файла вычисляет операция рядом с проверочным проектом. В первой версии отдельное правило для него потребуется только в том случае, если нужно независимо управлять его расположением. Обычные `.filters` аналогично создаются для соответствующего проекта из его проектных фильтров.

## 6. Компонент с нативной и управляемой библиотеками

```xml
<Component name="Telemetry">
  <Projects>
    <Project id="native" kind="library" projectType="native">
      <Files>
        <Header>Includes/Telemetry/UniversalDevKit/Telemetry/**/*.h</Header>
        <Source>Sources/Telemetry/Native/**/*.cpp</Source>
        <Group name="Projects">
          <Output format="project:shared">Projects/!Generated/MsBuild/{kind:title}/{name}/UniversalDevKit.{name}.Shared.{ext}</Output>
          <Output format="project:native">Projects/!Generated/MsBuild/{kind:title}/{name}/UniversalDevKit.{name}.{variant:title}.{ext}</Output>
        </Group>
        <Group name="BuildFiles">
          <CMake>Sources/Telemetry/Native/Build.cmake</CMake>
          <MSBuildTargets>Sources/Telemetry/Native/Build.targets</MSBuildTargets>
          <Output format="meta:props"
                  generate="dependencies">Projects/!Generated/MsBuild/{kind:title}/{name}/UniversalDevKit.{name}.Dependencies.{ext}</Output>
        </Group>
      </Files>
      <Filters>
        <Filter filter="{Tree:Solution}/Projects/!Generated/MsBuild/{kind:title}/{name}">
          <GroupRef>Projects</GroupRef>
        </Filter>
        <Filter filter="{Tree:Project}/Build">
          <GroupRef>BuildFiles</GroupRef>
        </Filter>
      </Filters>
    </Project>

    <Project id="dotnet" kind="library" projectType="classLibrary">
      <MSBuild>
        <Properties>
          <TargetFramework>net8.0</TargetFramework>
        </Properties>
      </MSBuild>
      <RuntimeDependencies>
        <Dependency projectId="native" variant="Dynamic" />
      </RuntimeDependencies>
      <Files>
        <Source>Sources/Telemetry/DotNet/**/*.cs</Source>
        <Group name="Projects">
          <Output format="project:classLibrary">Projects/!Generated/MsBuild/{kind:title}/{name}/UniversalDevKit.{name}.{framework}.{ext}</Output>
        </Group>
      </Files>
      <Filters>
        <Filter filter="{Tree:Solution}/Projects/!Generated/MsBuild/{kind:title}/{name}">
          <GroupRef>Projects</GroupRef>
        </Filter>
      </Filters>
    </Project>
  </Projects>
</Component>
```

У обычного нативного выхода движок подставляет каждый разрешённый вариант, например `Static` и `Dynamic`. Shared-выход вычисляется один раз. У управляемого проекта `framework` берётся из его настроек. У обеих групп `Projects` локальная область видимости. Связь .NET с нативной библиотекой задаётся через `projectId` и вариант, поэтому вычисленное имя `.vcxproj` не дублируется в ссылке.

Тот же шаблон декларации применяется к приложениям. Например, внутри проекта с `projectType="wpf"` подстановки дают путь к `.csproj` приложения:

```xml
<Output format="project:wpf">Projects/!Generated/MsBuild/{kind:title}/{name}/{name}.{ext}</Output>
```

## 7. Условный путь и дополнительный исходник

Если прямой шаблон пути становится недостаточен, внутри того же `Output` можно использовать `When / Default`. Здесь выход для варианта Dynamic получает отдельный каталог, а остальные варианты используют стандартный.

```xml
<Files>
  <Group name="GeneratedSources">
    <Output format="meta:cpp" template="Sources/Example/BuildInfo.cpp.in">
      <When variant="dynamic">Projects/!Generated/MsBuild/{kind:title}/{name}/Dynamic/BuildInfo.{ext}</When>
      <Default>Projects/!Generated/MsBuild/{kind:title}/{name}/BuildInfo.{ext}</Default>
    </Output>
  </Group>
</Files>
<Filters>
  <Filter filter="{Tree:Project}/Generated">
    <GroupRef>GeneratedSources</GroupRef>
  </Filter>
</Filters>
```

Первое подходящее условие выбирает путь. `Default` используется, если условия не подошли. В примере выход вычисляется в контексте выбранного варианта. На диске получится `BuildInfo.g.cpp`. Пример показывает генерацию и отображение файла. Автоматическое включение произвольного `meta:cpp` в компиляцию остаётся открытым вопросом.

## Форматы и проверка контракта

| Формат | `{ext}` | Как формируется содержимое |
|---|---|---|
| `project:native` | `vcxproj` | Встроенный генератор нативного проекта. Операция `headerCheck` создаёт проверочный проект |
| `project:shared` | `vcxitems` | Встроенный генератор Shared Project |
| `project:classLibrary`, `project:wpf`, `project:vsix` | `csproj` | Встроенный генератор соответствующего .NET-проекта |
| `meta:header` | `g.h` | Шаблон C++-заголовка |
| `meta:cpp` | `g.cpp` | Шаблон C++-исходника |
| `meta:props` | `g.props` | Шаблон либо расчёт зависимостей |
| `meta:targets` | `g.targets` | Шаблон либо расчёт интеграции исходников |

- Все пути на диске считаются от корня реестра. Шаблон выхода заканчивается на `.{ext}`. Точка задаётся схемой.
- Движок сначала вычисляет все выходы, затем по этому же плану формирует импорты и применяет фильтры. `{Tree:Solution}` размещает проект как проект решения, а обычный файл как `SolutionItem`.
- Неизвестный формат или операция, неподдерживаемая подстановка, отсутствующий шаблон, одновременные `template` и `generate`, выход за пределы корня и совпадение двух выходных путей дают ошибки до записи.
- Условия `When / Default` используют тот же механизм выбора, что и текущие правила именования проектов. Синтаксис переиспользования одного общего объявления `Output` несколькими компонентами пока открыт.
- Сгенерированный заголовок можно показать фильтром сразу. Подключение его каталога к компиляции остаётся настройкой сборки. Если понадобится создавать и компилировать произвольный `meta:cpp`, привязку к компиляции нужно отдельно выразить в контракте. У встроенного HeaderCheck эту связь уже устанавливает операция.