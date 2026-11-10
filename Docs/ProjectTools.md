# ProjectTools

Общий инструмент находится в Sources/Windows/ProjectTools и поставляется пакетом UniversalDevKit.ProjectTools. Контракт и способы запуска описаны в [README пакета](../Packages/Windows/ProjectTools/README.md).

Генерация UDK:

```powershell
pwsh -File Sources/Windows/ProjectTools/Generate.ps1 -ManifestPath Components.json
pwsh -File Sources/Windows/ProjectTools/Generate.ps1 -ManifestPath Components.json -Check
```

Scripts/PowerShell/GenerateComponentProjects.ps1 сохранён только для совместимости существующих проверок и Connect. Реализация перенесена в поставку ProjectTools. Connect и его контракт не изменены.

Shared и метаданные UDK формирует профиль UDK; библиотечные проекты и обновление solution выполняются общей точкой входа. Static/Dynamic теперь полностью генерируются. Существующие GUID сохраняются. Пользовательские настройки выносятся в buildExtensions. Изменение шаблона обновляет существующие проекты при следующем запуске.

Проверка нового инструмента: Tests/Infrastructure/TestProjectTools.ps1. Генерация SDK проверяется через пакетный Projects/Generate.csproj в AndroidAppPreviewer. NuGet-пакет собирается обычным PackageTools из Packages/Windows/ProjectTools/Package.json; публикация выполняется отдельно.

ProjectTools 0.2.0 поставляет проверяемый архив SolutionInjector v1.1.0-dev и использует sync вместо вставки проектов. Владение хранится в GlobalSection(SolutionInjectorProjectOwnership) самого решения. Обновление конфигураций и Shared-ссылок, перемещение и удаление управляемых записей проверяются на временной копии до записи основного solution. Connect и Scripts/Tools/SolutionInjector.json остаются на прежней версии. Для тестовых реестров используются отдельные минимальные solutions, чтобы они не наследовали владение рабочими компонентами UDK.