# UniversalDevKit.PackageTools

Самостоятельный инструмент сборки проектов и упаковки NuGet по JSON-описаниям. Checkout UniversalDevKit для использования не требуется. Поддерживаются Windows PowerShell 5.1 и PowerShell 7, .NET build/publish, CMake build/install, поставка файлов и восстановление закреплённых NuGet-зависимостей.

Добавьте PackageReference на `UniversalDevKit.PackageTools` в служебный SDK-style csproj, задайте `UdkPackageRepository` и элементы `UdkPackage` с путями к Package.json. Команда `dotnet msbuild Packages/Build.csproj -restore -t:PackRepository` восстановит закреплённую версию инструмента и выпустит выбранные пакеты. `-t:PlanRepositoryPackages` проверяет планы без сборки.

Параметры MSBuild: `UdkPackageSources` для NuGet-зависимостей, `UdkPackageOutput` для выходного каталога, `UdkPackageNuGet`, `UdkPackageCMake`, `UdkPackagePowerShell` для инструментов. Источники восстановления самого PackageReference задаются обычным NuGet.Config или RestoreAdditionalProjectSources.

Установленный пакет содержит `tools/Build.ps1`, все адаптеры и helpers, закреплённый SHA-256 manifest NuGet.exe и автоматически импортируемый `build/UniversalDevKit.PackageTools.targets`. NuGet.exe при необходимости загружается в `!tools` собираемого репозитория с проверкой SHA-256. Инструмент не публикует пакеты в удалённые feeds; публикация выполняется отдельным действием CI.

Delivery.json поддерживает dependencies: массив id/version с точными версиями. Адаптер NuGet подставляет их в {{DEPENDENCIES}} nuspec как точные зависимости [version]. Это позволяет выпускать SDK с обычными NuGet-зависимостями без включения сторонних бинарников в payload.

Начиная с 0.1.3 projects в Package.json может быть объектом локальных определений вместо пути к реестру. Ключ объекта задаёт имя; adapter, artifacts и параметры проекта находятся в значении. Поля name и schemaVersion не дублируются. dependencies адресуются внутри пакета, а рабочие каталоги изолируются по имени пакета. Пути проектов остаются относительными корню репозитория. Внешние реестры продолжают поддерживаться.

Версия 0.2.0 переводит собственные выпуски UDK на тот же механизм: выбор -Delivery, фильтры contents.deliveries, releaseDependencies, чтение properties-версий, cmake-build, udk-native, udk-prefab и gradle-publish, доставки maven-prefab и maven-repository. Все продуктовые Package.json используют версию 2; Delivery.json имеет независимую версию 1. Старые упаковщики удалены.