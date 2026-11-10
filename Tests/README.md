# Проверки UniversalDevKit

**Навигация:** [Главная](../README.md) → Проверки

Общий runner: Tests/Scripts/RunAllTests.cmd либо Tests/Scripts/PowerShell/RunAllTests.ps1. Параметр ListOnly показывает актуальный список. Group выбирает Windows, Android или All; Test — отдельные сценарии. Логи и summary.csv сохраняются в !artifacts/tests.

## Рабочие компоненты

- [Diagnostic](Integration/Diagnostic/README.md) проверяет Windows DLL, потоки, контекст, завершение работы и process-state. RunDiagnosticTests.cmd относится к рабочему Diagnostic.
- [Native PackageReference](Integration/Packages/NuGet.PackageReference.Tests.ps1) проверяет Helpers и Diagnostic, а при явном выборе — XamlRuntime/OpenGLESRenderer.
- [Android Prefab](Integration/Packages/AndroidPrefab.Tests.ps1) проверяет APK и SO для Helpers/Diagnostic, с отдельным запуском на устройстве.
- [Kotlin Maven](Integration/Packages/AndroidKotlin.Tests.ps1) проверяет AndroidCoreSdk/AndroidAppKit и зависимости.
- Проверки Windows Previewer перенесены в отдельный репозиторий [AndroidAppPreviewer](https://github.com/isrepeat/AndroidAppPreviewer): Tests/PreviewerSmoke проверяет ABI плагина, навигацию, ANGLE и hot reload, а Tests/PackageRelease.Tests.ps1 — готовый PluginSDK и его NuGet-зависимости.
- [XamlRuntime](XamlRuntime/README.md) имеет отдельные проверки runtime и анимаций.

## Инфраструктура и независимые fixtures

Рабочие компоненты не используются как универсальные заглушки. Графы зависимостей проверяет отдельный Diamond fixture; публичный экспорт — ExportProbe; header-only доставка — HeaderProbe/HeaderLeaf; общие настройки компиляции — CompileProbe.

```powershell
./Tests/Scripts/PowerShell/RunTests.ps1 -Scenario Diamond,Export
```

RunTests поддерживает WorkingTree и Submodule. Для Submodule задайте Revision с нужными изменениями. Каждый сценарий получает изолированную копию библиотеки и consumer; успешная сборка не заменяет проверку запуска. Diamond проверяет Shared/Static/Dynamic, private/static и точный набор транзитивных DLL. Export проверяет публичный и внутренний символы DLL.

TestBinaryCompatibility.ps1 использует ExportProbe и проверяет CRT, iterator ABI, архитектуру, toolset и защиту install prefix. TestRegistryContract.ps1, TestComponentRegistry.ps1, TestBuildExtensions.ps1 и TestCompileSettings.ps1 проверяют генерацию и контракты без зависимости от состава рабочего реестра.

NuGet.Registry.Tests.ps1 использует HeaderProbe → HeaderLeaf; общие Windows props/targets для Diamond находятся в Fixtures/Packages/NativeComponent. PackageDelivery.Tests.ps1 проверяет отдельные механизмы доставки на synthetic-fixtures.

## Запуск и отчёты

Точки входа RunDiamond.cmd и RunExport.cmd выбирают соответствующий MSBuild-сценарий. RunDiamondMatrixTests.cmd проверяет CMake/NuGet графы; RunNuGetRegistry.cmd и RunNuGetPackageReferenceTests.cmd — текущие пакетные сценарии.

Android-тесты требуют SDK/NDK/JDK; запуск требует устройства и Serial. BuildPassed-DeviceNotRun и DeviceNotRun не означают успешный запуск. Для обычной проверки приложения используйте [Android-гайд](../Docs/AndroidBuild.md).