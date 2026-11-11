# AndroidBuildTools

Пользовательские команды и настройка окружения: [гайд Android-приложений](../../../Docs/AndroidBuild.md).

Перенесённые инструменты сборки приложений Android из UtilityHelpersLib. NuGet ID `AndroidBuildTools` сохранён; версия поставки — `1.0.63.31`. Версия задаётся полем `version` в `Package.json`.

Сборка пакета: `Scripts/Packages/Android/Pack.AndroidBuildTools.cmd`. Результат: `!artifacts/packages/nuget/AndroidBuildTools`. Реализация находится в Sources/Android/AndroidBuildTools: PowerShell, Cmake, Gradle и ApplicationFramework. Публичные C++ заголовки находятся в Includes/Android/AndroidBuildTools, проекты сборки — в Projects/Gradle/AndroidBuildTools и Projects/Cmake/AndroidBuildTools. Delivery/NuGet/Delivery.json задаёт отображение этих каталогов в tools, cmake, gradle и build/native внутри пакета.

Проект закрепляет AndroidBuildToolsVersion в android-build.psd1. Команда `build.ps1 restore` восстанавливает инструменты; `build.ps1 build-android -Configuration Debug` генерирует XAML и запускает Gradle. Новый Native.Prefab использует AGP externalNativeBuild, AAR UDK и c++_shared вместо старого монолитного XamlRuntime NuGet и c++_static. NativeOnly запускает externalNativeBuild без упаковки APK. Для текущего профиля UDK native-зависимости и CMake используют Release, включая Debug APK.

XAML-компилятор восстанавливается из отдельного `UniversalDevKit.XamlCompiler`. NuGet и Maven feed настраиваются через Android.SharedProps.json; Maven source можно переопределить androidMavenSource или ANDROID_MAVEN_SOURCE. Kotlin-зависимости AndroidAppKit/CoreSdk сохраняют свои координаты и версии. Старый standalone CMake-режим оставлен для совместимости существующих проектов; новый шаблон его не использует.

Команды signing, version, Drive и распределения перенесены без изменения протоколов. Они выполняются только при явном вызове. Перенос Preview SDK и перевод рабочих приложений выполняются отдельно; preview нового шаблона пока не поддерживается.


Публичные C++ заголовки: UniversalDevKit/Android/AndroidBuildTools/ApplicationFramework/...; namespace universaldevkit::android::androidbuildtools::applicationframework. Заголовки поставляются отдельно от реализации, в build/native/include.