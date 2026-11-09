# Windows native NuGet

**Навигация:** [Главная](../../../README.md) → [Пакеты](../../README.md) → Native NuGet

Упаковщик Build.ps1 читает Components.json и Package.json с NuGet delivery adapter=component. По умолчанию выбираются компоненты, имеющие Windows component-adapter; составные инструменты и Preview SDK выпускаются своими Build.ps1.

## Выпуск

```powershell
./Packages/Build/NuGet/Build.ps1 -Components Helpers,Diagnostic -LicenseFile ./LICENSE
```

Можно указать CMake, NuGet и OutputDirectory. Версия читается из корневой Version.json. Каждый корень имеет изолированный каталог в !artifacts/packages/nuget/<component>; необходимая подготовка внешних зависимостей вызывается через delivery. Для XAML и renderer используются их отдельные CMD-точки в Scripts/Packages/CrossPlatform.

Helpers поставляется как header-only Shared. Diagnostic имеет process-state и поставляется только Dynamic с Dynamic CRT. XamlRuntime и OpenGLESRenderer имеют Static/Dynamic и используют Dynamic CRT; renderer также доставляет ANGLE. Нельзя выбирать варианты, отсутствующие в конкретном delivery.

## Подключение через native PackageReference

В поддерживающем MSBuild включите EnableNativePackageReferenceSupport до Microsoft.Cpp.Default.props:

```xml
<PropertyGroup Label="Globals">
  <EnableNativePackageReferenceSupport>true</EnableNativePackageReferenceSupport>
  <UniversalDevKitComponents>Diagnostic</UniversalDevKitComponents>
  <UniversalDevKitRuntime>Dynamic</UniversalDevKitRuntime>
  <UniversalDevKitDiagnosticLinkage>Dynamic</UniversalDevKitDiagnosticLinkage>
</PropertyGroup>
<ItemGroup>
  <PackageReference Include="UniversalDevKit.Diagnostic" Version="[0.1.0]" />
</ItemGroup>
```

Используйте версию из своего выпуска. Поддержка проверялась на Visual Studio 2026 / MSBuild 18.11. На старых версиях используйте packages.config. NuGet восстанавливает зависимости; buildTransitive-импорты применяют согласованные props/targets. Для packages.config нужны явные импорты интеграции восстановленных пакетов.

В проектах с несколькими корнями UniversalDevKitComponents должен перечислять именно выбранные корни. Итоговый набор .lib, определений, include-путей и DLL вычисляется общим графом зависимостей. Конфликт Static/Dynamic или несовпадение версий отклоняется до компиляции.

## Контракт выпуска

Delivery задаёт ID, supportedPlatforms, supportedRuntimes, nuspec и integration. Props/targets компонента находятся в Delivery/NuGet; упаковщик формирует Generated/Settings.props и Settings.targets. Пакет подключает их явными imports.

Метаданные binaries/<runtime>/<configuration>/Release.json фиксируют toolset, MSVC tools, архитектуру, CRT и конфигурацию. Принудительно подключаемый Abi.h проверяет фактический CRT, iterator debug level и компилятор. Debug нельзя неявно подменять Release. Импортная .lib нужна для линковки DLL; сама DLL должна доставляться к запускаемому приложению.

## Проверки

- [NuGet.PackageReference.Tests.ps1](../../../Tests/Integration/Packages/NuGet.PackageReference.Tests.ps1) — Helpers и Diagnostic по умолчанию, а также явно выбранные XAML-компоненты.
- [NuGet.Registry.Tests.ps1](../../../Tests/Integration/Packages/NuGet.Registry.Tests.ps1) — отдельный header-only реестр HeaderProbe → HeaderLeaf.
- [Diamond.Tests.ps1](../../../Tests/Integration/Cmake/Diamond.Tests.ps1) — общие графы CMake и NuGet, private/public требования и транзитивные DLL.

Изолированный шаблон Windows component-delivery для synthetic-fixtures находится в Tests/Fixtures/Packages/NativeComponent. Он не является компонентом или выпускаемым пакетом UDK.