# Проверки доставки пакетов

Эти пакеты — изолированные fixtures инфраструктуры, не новая реализация UDK. Версия 1.0.0 фиксирована; каждый тест создаёт собственный feed и cache под !artifacts. Они не публикуются в пользовательские feeds.

| Семейство | Покрываемые существующие пакеты | Проверка |
|---|---|---|
| NativeWindows | Native-часть CppFeatures, CrashHandling, XamlRuntime | Существующий NuGet.Tests.ps1: Helpers/Diagnostic, CRT, Static/Dynamic, Debug/Release |
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

Android-проверки подтверждают упаковку и сборку, но не запуск на устройстве. APK можно установить отдельно; MainActivity проверяет AppKit и транзитивный Core и пишет UdkPackagePackageDelivery: PASS. Prefab/JNI отсутствуют: существующие CoreSdk/AppKit содержат Kotlin, а Android-native сценарий отражает доставку через NuGet.

Managed packagedelivery не подтверждает WinRT-активацию, C++/CX, UWP или .NET Framework 4.7.2. WinRt packagedelivery проверяет raw ABI и фабрику напрямую, но не регистрацию класса через RoGetActivationFactory, IDL/WinMD и CsWinRT-проекцию. Эти дополнительные платформенные поверхности остаются отдельной матрицей; обычная .NET DLL не заменяет такую проверку. Подробные результаты записываются в summary.csv; отсутствующие инструменты завершают выбранный сценарий ошибкой.