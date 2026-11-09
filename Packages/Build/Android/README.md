# Android AAR/Prefab

**Навигация:** [Главная](../../../README.md) → [Пакеты](../../README.md) → Android

Полный пользовательский цикл создания приложения, превью и APK описан в [гайде Android](../../../Docs/AndroidBuild.md). Этот раздел описывает поставку C++-компонентов.

## Профиль

NDK r27c (27.2.12479018), API 24+, arm64-v8a/x86_64, c++_shared, Release и поддержка 16-KiB страниц. Рабочие компоненты: Helpers (header-only), Diagnostic (Dynamic/process-state), XamlRuntime и OpenGLESRenderer (Static/Dynamic). Windows Preview SDK не имеет Android delivery.

## Выпуск

```powershell
./Packages/Build/Build.ps1 -PackagePath Packages/CrossPlatform/Diagnostic/Package.json -Delivery Android -AndroidNdk C:/Android/Sdk/ndk/27.2.12479018 -Abi arm64-v8a -Configuration Release
```

CMake и Ninja могут быть переданы явно; по умолчанию используются инструменты Visual Studio. Все Android-поставки выбираются через -All -Delivery Android. Версия читается через versionSource. Проекты udk-prefab готовят native payload, maven-prefab формирует AAR/POM. Проекты gradle-publish и доставка maven-repository выпускают AndroidCoreSdk и AndroidAppKit тем же механизмом; releaseDependencies AppKit предварительно выпускает CoreSdk. Шаблон native Consumer.cmake хранится в Sources/PackageTools/Templates.

Maven group — org.universaldevkit. Например, Diagnostic поставляется как universaldevkit-diagnostic-dynamic-release, Helpers — universaldevkit-helpers-shared-release. AAR включает Prefab-заголовки, библиотеки и описание совместимости; Maven POM сохраняет зависимости. Потребителю не нужен исходный checkout UDK.

## Подключение

Gradle включает prefab и зависимость нужной версии:

```kotlin
android { buildFeatures { prefab = true } }
dependencies {
    implementation("org.universaldevkit:universaldevkit-diagnostic-dynamic-release:0.1.0")
}
```

Maven-репозиторий задаётся в settings.gradle.kts. В текущем AndroidTemplates его настройки поступают из Android.SharedProps.json через AndroidBuildTools.

```cmake
find_package(udk_diagnostic_dynamic CONFIG REQUIRED)
get_target_property(udk_include udk_diagnostic_dynamic::Diagnostic INTERFACE_INCLUDE_DIRECTORIES)
include("${udk_include}/UniversalDevKit/Android/Consumer.cmake")
add_library(app SHARED Main.cpp)
udk_android_link(app udk_diagnostic_dynamic::Diagnostic)
```

udk_android_link передаёт публичные требования, доставляет SO и проверяет несовместимые варианты, STL и версии. Для native-приложения используется c++_shared; process-state Diagnostic должен быть одним экземпляром SO для всех модулей.

## Проверка

[AndroidPrefab.Tests.ps1](../../../Tests/Integration/Packages/AndroidPrefab.Tests.ps1) собирает APK для Helpers и Diagnostic по умолчанию. XamlRuntime/OpenGLESRenderer выбираются через Components. Тест проверяет состав SO и отрицательные сценарии. По Serial доступно instrumentation; SkipDevice означает только сборку.

Сборка arm64 Debug APK нового AndroidTemplates проверена. Запуск на устройстве, отрисовка, ввод и lifecycle подтверждаются отдельно. AndroidKotlin.Tests.ps1 проверяет Kotlin/Maven-зависимости независимо от native-профиля.