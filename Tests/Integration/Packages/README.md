# Проверки доставки пакетов

## Реальные компоненты UDK

Kotlin-пакеты AndroidCoreSdk и AndroidAppKit перенесены в Packages/Android. Реальная поставка проверяется AndroidKotlin.Tests.ps1: публикация обоих AAR в отдельный Maven feed, точная зависимость CoreSdk и компиляция независимого Kotlin-потребителя. AndroidMaven в таблице ниже остаётся тестовой заглушкой инфраструктуры.

- [Windows native NuGet](../../../Packages/Build/NuGet/README.md): NuGet.Tests.ps1, NuGet.Registry.Tests.ps1 и NuGet.PackageReference.Tests.ps1.
- [Android AAR/Prefab](../../../Packages/Build/Android/README.md#проверка): [AndroidPrefab.Tests.ps1](AndroidPrefab.Tests.ps1), независимый [APK-потребитель](../../Fixtures/Consumers/AndroidPrefab), Static/Dynamic HeleprsTest/DiagnosticTest, состав SO и отрицательные проверки совместимости.

Для Android `RunAndroidPrefabTests.cmd -SkipDevice` проверяет сборку без устройства. Запуск instrumentation выполняется без SkipDevice с выбранным Serial; только UDK_RESULT=PASS подтверждает вызов API на Android. Существующие отчёты BuildPassed-DeviceNotRun подтверждают сборку APK, но не runtime.

## Заглушки способов доставки

Эти пакеты — изолированные fixtures инфраструктуры, не новая реализация UDK. Версия 1.0.0 фиксирована; каждый тест создаёт собственный feed и cache под !artifacts. Они не публикуются в пользовательские feeds.

| Семейство | Покрываемые существующие пакеты | Проверка |
|---|---|---|
| NativeWindows | Native-часть CppFeatures, CrashHandling, XamlRuntime | Существующий NuGet.Tests.ps1: HeleprsTest/DiagnosticTest, CRT, Static/Dynamic, Debug/Release |
| Managed | Managed-доставка PluginSDK и проекций | net8.0 DLL, PackageReference, сборка и вызов |
| WinRt | WinRT ABI CppFeatures/CrashHandling и host-инструмент XamlRuntime | DLL из NuGet, IActivationFactory/IInspectable, создание объекта и вызов интерфейса; запуск EXE из tools/win-x64 |
| BuildTools | AndroidBuildTools | Инструмент из NuGet выполняется через buildTransitive и генерирует файл consumer |
| Templates | AndroidTemplates | NuGet install, создание проекта скриптом пакета, сборка и запуск |
| AndroidNative | Android-бинарники XamlRuntime | NDK API 24, arm64-v8a по умолчанию, .a в NuGet, восстановление и линковка отдельного .so |
| AndroidMaven | AndroidCoreSdk, AndroidAppKit | Две Kotlin AAR, POM и sources JAR, публичная транзитивная зависимость, отдельный APK consumer |

Обычный запуск Windows-заглушек:

```powershell
./Tests/Integration/Packages/PackageDelivery.Tests.ps1
./Tests/Integration/Packages/PackageDelivery.Tests.ps1 -Family NativeWindows
./Tests/Integration/Packages/PackageDelivery.Tests.ps1 -Family WinRt -CMake C:/tools/cmake.exe
```

Android запускается явно, без молчаливого пропуска отсутствующих инструментов:

```powershell
./Tests/Integration/Packages/PackageDelivery.Tests.ps1 -Family AndroidNative -CMake C:/tools/cmake.exe -AndroidNdk C:/Android/ndk/27.2.12479018
./Tests/Integration/Packages/PackageDelivery.Tests.ps1 -Family AndroidMaven -Gradle C:/tools/gradle-8.11.1/bin/gradle.bat -JavaHome C:/tools/jdk-17 -AndroidSdk C:/Android/sdk
```

Для AndroidNative нужен Ninja в PATH. AndroidMaven использует Gradle 8.11.1, JDK 17 или 21, AGP 8.9.1, Kotlin 2.1.20, compileSdk 36/minSdk 23 и Build Tools 36.0.0. Первый запуск загружает Gradle-зависимости из Google/Maven Central. Параметр GradleCache позволяет повторно использовать кеш инструментов; по умолчанию создаётся отдельный кеш запуска. Координаты наших fixtures фиксированы; consumer получает AppKit из временного Maven feed, без project reference на Core.

Эти Android-заглушки подтверждают упаковку и сборку, но не запуск на устройстве. APK можно установить отдельно; MainActivity проверяет AppKit и транзитивный Core и пишет UdkPackagePackageDelivery: PASS. В заглушках Prefab/JNI отсутствуют: CoreSdk/AppKit содержат Kotlin, а AndroidNative отражает доставку через NuGet. Реальные AAR/Prefab UDK проверяются отдельным AndroidPrefab.Tests.ps1, описанным выше.

WinRt проверяет Windows x64 Release: IDL компилируется midlrt в WinMD и включается в NuGet вместе с DLL. Native Desktop восстанавливает пакет только из локального feed, генерирует C++/WinRT-проекцию SDK-инструментом и активирует класс через манифест EXE. C# consumer использует PackageReference и CsWinRT 2.2.0, генерирует проекцию из WinMD пакета и также выполняет штатную активацию. Системная регистрация и прямой вызов DllGetActivationFactory не используются.

Запуск: Tests/Scripts/RunWinRtPackageTests.cmd либо powershell.exe -NoProfile -File Tests/Integration/Packages/PackageDelivery.Tests.ps1 -Family WinRt. CMake обнаруживается в Visual Studio; C# fixture использует Windows SDK 10.0.26100.0. Восстановление C# имеет отдельный пустой cache и packageSourceMapping: тестовые пакеты только из временного feed, инструменты Microsoft из NuGet.org. Первый запуск требует сети.

Оба EXE запускаются из отдельных чистых каталогов с ограниченным PATH. Затем повторяются запуски без DLL компонента; отказ активации обязателен. activation.log сохраняется рядом с каждым EXE, summary.csv — в корне окружения. C++/CX, UWP, .NET Framework 4.7.2 и упаковка MSIX остаются отдельными сценариями.