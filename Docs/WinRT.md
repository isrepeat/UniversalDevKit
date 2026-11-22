# WinUI и C++/WinRT

ProjectTools поддерживает цепочку `C# winui → C++ winrt → C++ native`. Приложения пока только unpackaged: `WindowsPackageType=None`. MSIX не генерируется.

Рабочий пример находится в [Tests/Fixtures/WinRT](../Tests/Fixtures/WinRT/Components.xml). Генерируйте его на отдельной копии; результат проверки и сборки хранится в `!artifacts/` этой копии.

## Описание проектов

Каждый компонент имеет собственное имя. Точки сохраняются в путях и именах библиотек. Для export-макросов точки заменяются подчёркиваниями: `HelloWorld.Core` получает `UNIVERSALDEVKIT_HELLOWORLD_CORE_API`. Сегменты native-имени начинаются с латинской буквы.

```xml
<Component name="HelloWorld.WinRT">
  <Projects>
    <Project id="winrt" kind="library" projectType="winrt">
      <Projection assemblyName="HelloWorld.WinRT.Projection"
                  targetFramework="net10.0-windows10.0.26100.0" />
      <Files>
        <Input role="header">Sources/WinRT/Greeter.h</Input>
        <Input role="source">Sources/WinRT/Greeter.cpp</Input>
        <Input role="source">Sources/WinRT/Greeter.idl</Input>
      </Files>
      <Dependencies>
        <Dependency component="HelloWorld.Core" visibility="private" linkage="static" />
      </Dependencies>
    </Project>
  </Projects>
</Component>
```

WinRT-компонент всегда собирается как DynamicLibrary. `Projection` задаёт имя отдельной .NET-сборки и её Windows TargetFramework. Имя проекции должно отличаться от имени native DLL. `RootNamespace` компонента совпадает с его именем. IDL описывает классы этого namespace; реализация и IDL остаются пользовательскими исходниками.

```xml
<Component name="HelloWorld">
  <Projects>
    <Project id="application" kind="application" projectType="winui">
      <Files><Input role="source">Sources/Application/**/*</Input></Files>
      <MSBuild>
        <Properties>
          <TargetFramework>net10.0-windows10.0.26100.0</TargetFramework>
        </Properties>
      </MSBuild>
      <Dependencies>
        <Dependency component="HelloWorld.WinRT" visibility="private" linkage="dynamic" />
      </Dependencies>
    </Project>
  </Projects>
</Component>
```

Добавьте исходники WinUI в описание компонента. `App.xaml` и код запуска хранятся в исходниках приложения вместе с его окнами. Поддерживаются C#, XAML, RESW, манифесты и изображения. `App.xaml` получает роль ApplicationDefinition, другие XAML — Page, RESW — PRIResource.

В схеме 7 в реестр добавляются три шаблона выходов:

```xml
<Output role="project-winui">{projectDirectory}/{name}.{ext}</Output>
<Output role="project-winrt">{projectDirectory}/{name}.{ext}</Output>
<Output role="project-winrtProjection">{projectDirectory}/{name}.Projection.{ext}</Output>
```

Остальные общие выходы схемы 7 сохраняются. Вспомогательный проект проекции не регистрируется вручную; генератор добавляет его в solution. Для WinUI и проекции solution использует native-платформу, а не Any CPU. Поддерживаются x64, ARM64 и Win32; проверенный интеграционный пример использует x64.

## Сборка и манифест

Требуются Visual Studio с C++ build tools, Windows SDK 10.0.26100.0 и .NET SDK для выбранного TargetFramework. Используйте MSBuild Visual Studio, поскольку сборка включает `.vcxproj` и WinUI XAML compiler.

```powershell
udk project generate Components.xml
MSBuild HelloWorld.sln /restore /p:Configuration=Debug /p:Platform=x64
```

Закреплены Microsoft.Windows.CppWinRT 2.0.250303.1, Microsoft.Windows.CsWinRT 2.3.1 и Microsoft.WindowsAppSDK 1.8.260921001. Восстановление WinRT-проекта выполняется через автоматически созданный вспомогательный SDK-проект; native-проект импортирует C++/WinRT из глобального NuGet-кэша. `NUGET_PACKAGES` учитывается.

Выбран исходный режим поставки: Windows App SDK self-contained и .NET framework-dependent. Эти настройки независимы от unpackaged. На машине запуска нужен соответствующий .NET Runtime; Windows App SDK размещается рядом с приложением. Настройки `WindowsAppSDKSelfContained` и `SelfContained` можно переопределить свойствами приложения.

После сборки native-компонента C#/WinRT генерирует проекцию в отдельном производящем проекте. Приложение ссылается на готовую .NET-сборку. Генерация выполняется при обычной проектной сборке, без предварительной упаковки NuGet.

MSBuild-задача читает `.winmd`, находит runtime-классы с Activatable, Static или Composable и учитывает ThreadingAttribute. Из этого формируется фрагмент регистрации. Приложение объединяет фрагменты всех своих WinRT-зависимостей, включая транзитивные, с базовым манифестом и встраивает результат в EXE. Повторные одинаковые регистрации объединяются, конфликтующие DLL или threadingModel приводят к ошибке сборки.

Для своего базового манифеста задайте `msbuild.properties.ApplicationManifest` путём относительно корня реестра. Исходный файл не переписывается. Результат находится в промежуточном каталоге как `UniversalDevKit.Application.g.manifest`. Без настройки создаётся базовый манифест с `asInvoker`. Список WinRT-классов в XML UDK не нужен.

## NuGet

Производитель упаковывает автоматически созданный проект проекции:

```powershell
MSBuild Projects/!Generated/MsBuild/Library/HelloWorld.WinRT/HelloWorld.WinRT.Projection.csproj /restore /t:Pack /p:Configuration=Release /p:Platform=x64 /p:PackageOutputPath=C:/LocalFeed
```

Пакет содержит готовую проекцию в `lib/<TFM>`, native DLL в `runtimes/win-<architecture>/native`, фрагмент активации, buildTransitive targets и задачи работы с манифестом. Динамические native-зависимости Core также входят в пакет. C#/WinRT остаётся зависимостью для runtime/compile assets; его build-интеграция не передаётся потребителю.

По умолчанию Pack собирает native DLL для платформ реестра. Свойство `UniversalDevKitWinRTPackagePlatforms` позволяет выбрать подмножество; для каждой выбранной платформы должны быть установлены C++ build tools. Проекция остаётся одной .NET-сборкой.

Потребителю достаточно PackageReference на пакет, Windows TargetFramework, `WindowsPackageType=None` и согласованного RuntimeIdentifier. Native DLL доставляются стандартным механизмом NuGet в build/publish; buildTransitive автоматически дополняет манифест. Потребитель не получает IDL или WinMD для генерации проекции.

Если WinRT-компонент использует другой WinRT-компонент, производящий проект проекции получает ссылку на его готовую проекцию и метаданные для разрешения типов. Для NuGet каждый такой проект упаковывается отдельно; ссылка превращается в зависимость пакета. Приложение получает транзитивные фрагменты манифеста через buildTransitive.

Проверка: `Tests/Infrastructure/TestWinRT.ps1`. Она собирает и запускает цепочку через проектные ссылки, затем через локальный NuGet и publish. Отдельно проверяется динамическая Core DLL. Ключ `-SkipBuild` оставляет проверки генерации.

Первичные источники: [C++/WinRT MSBuild targets](https://github.com/microsoft/cppwinrt/blob/master/nuget/Microsoft.Windows.CppWinRT.targets), [C#/WinRT projections](https://github.com/microsoft/CsWinRT/blob/master/docs/usage.md), [desktop application manifests](https://learn.microsoft.com/en-us/windows/win32/sbscs/application-manifests).