# Android AAR / Prefab

**Навигация:** [Главная](../../../README.md) → [Пакеты](../../README.md) → Android AAR/Prefab. См. также [общие проверки](../../../Docs/Validation.md#проверить-android-aarprefab) и [отличие от тестовых заглушек](../../../Tests/Integration/Packages/README.md).

Первый профиль: реальные Helpers/Diagnostic, точный NDK r27c 27.2.12479018, API 24+, arm64-v8a/x86_64, libc++ c++_shared, C++17. Проверка APK использует SDK/build-tools 36, JDK 21, Gradle 9.5 и AGP 9.3.2. Проверенный пакетный профиль — Release; Debug создаётся отдельно и требует отдельного прогона consumer.

## Инструменты

Scripts/Android/Toolchain.json закрепляет NDK и JDK. Общий ResolveToolchain.ps1 ищет SDK через ANDROID_HOME/ANDROID_SDK_ROOT и стандартные каталоги; NDK — через ANDROID_NDK_HOME/ANDROID_NDK_ROOT, SDK/ndk/<version> и стандартную установку r27c; JDK — через JAVA_HOME/JDK_HOME и стандартные каталоги. Явные AndroidSdk/AndroidNdk/JavaHome имеют приоритет; несовместимая явно выбранная установка отклоняется. NDK и JDK автоматически не устанавливаются.

Тест по умолчанию использует собственный Scripts/Android/Gradle/gradlew.bat. Версия Gradle 9.5.0 и SHA-256 дистрибутива закреплены в gradle-wrapper.properties; Wrapper восстанавливает Gradle в GRADLE_USER_HOME (по умолчанию ~/.gradle). Исходники UtilityHelpersLib не требуются. Параметр Gradle позволяет передать отдельный исполняемый файл; ответственность за его версию тогда лежит на вызывающем. На первом запуске Wrapper необходим доступ к services.gradle.org. Gradle нужен для APK-потребителя, упаковщик AAR использует только NDK/CMake/Ninja.

Для локального build-only теста достаточно ./Tests/Scripts/RunAndroidPrefabTests.cmd -SkipDevice; для запуска добавьте Serial и уберите SkipDevice. Все пути инструментов можно переопределить аргументами. Поле gradleVersion в Toolchain.json описывает профиль, фактическую загрузку фиксируют URL и checksum Wrapper.

## Сборка

```powershell
./Packages/Build/Android/Build.ps1 -AndroidNdk <ndk> -CMake <cmake.exe> -Ninja <ninja.exe> -OutputDirectory <new-local-feed>
```

Скрипт собирает штатный CMake UDK без копии реализации, читает реестр, существующий Resolve-UdkLinkageGraph и метаданные фактических бинарников. Определения адаптеров находятся в Packages/CrossPlatform/<компонент>/Delivery/Android/Delivery.json; Package.json связывает их с компонентами. Version.json остаётся источником версии. Новому compiled-компоненту нужны запись в реестре и адаптер. Header-only корни пока не поддерживаются; неописанные компоненты отклоняются.

Каталоги NDK-сборок изолированы по ABI в !artifacts/Android/cmake. Параметр BuildRoot разрешает повторно использовать свой каталог внутри !artifacts; CMake повторно конфигурирует и собирает изменённые исходники. Пакетный staging всегда новый. Существующий AAR по тому же адресу не перезаписывается: для повторной проверки используйте новый feed. Внешняя публикация не выполняется.

На компонент выпускаются независимые Maven-артефакты:

```text
org.universaldevkit:universaldevkit-helpers-static-release:<version>
org.universaldevkit:universaldevkit-helpers-dynamic-release:<version>
org.universaldevkit:universaldevkit-diagnostic-static-release:<version>
org.universaldevkit:universaldevkit-diagnostic-dynamic-release:<version>
```

Каждый AAR содержит все выбранные ABI, Prefab schema 2, заголовки public requirements, MIT LICENSE и udk-release.json. Транзитивные бинарники данного корня упакованы внутрь его AAR: отдельный Maven-пакет зависимости для этого не нужен. Отдельные AAR можно подключать вместе через адаптер, который проверяет конфликты версий и вариантов на одном target.

У Diagnostic.Static архив Helpers.Static находится во внутреннем Prefab-модуле без публичных заголовков. Diagnostic.Dynamic уже включает private Helpers.Static и не доставляет Helpers DLL/SO. Public-зависимости передают заголовки; private-зависимости участвуют в линковке/runtime без раскрытия include-путей. Prefab описывает связи модулей, включая необходимые shared-библиотеки. Runtime-only связь Prefab выражается внутренним модулем без заголовков; это может добавлять библиотеку к финальной команде линковки.

Сгенерированные пакетные Export.h включают import-макросы выбранного Dynamic-варианта; оригиналы в Includes не меняются. Только публичные заголовки и бинарники попадают в пакет, абсолютные пути checkout не нужны.

## Подключение

Gradle получает Maven-координаты и включает buildFeatures.prefab. Для первого профиля используйте тот же NDK и ANDROID_STL=c++_shared, minSdk >= 24. Для release-сборки задайте CMAKE_BUILD_TYPE=Release: AGP по умолчанию использует RelWithDebInfo. Пример проекта целиком находится в Tests/Fixtures/Consumers/AndroidPrefab.

```cmake
find_package(udk_diagnostic_dynamic CONFIG REQUIRED)
get_target_property(udk_include udk_diagnostic_dynamic::Diagnostic INTERFACE_INCLUDE_DIRECTORIES)
include("${udk_include}/UniversalDevKit/Android/Consumer.cmake")
udk_android_link(MyNativeTarget udk_diagnostic_dynamic::Diagnostic)
```

Используйте udk_android_link, а не обходной target_link_libraries: адаптер проверяет schema/version, точный NDK, API, configuration, c++_shared и все транзитивные варианты. Проверка действует на один конечный native target. Подключение UDK через несколько независимых SO требует согласованного состава пакетов всего приложения; модульное статическое состояние не становится общим состоянием процесса. Process-компоненты сохраняют обязательный Dynamic. Выгрузка библиотек не входит в текущий сценарий.

NDK libc++_shared.so не копируется в каждый AAR: её единственный экземпляр доставляет сборка приложения тем же NDK. У остальных SO приложения тоже должен быть согласованный runtime. Для arm64/x86_64 включена поддержка 16-KiB страниц. Произвольные ABI-флаги libc++ и другие NDK пока не являются поддержанным профилем.

## Проверка

```powershell
./Tests/Integration/Packages/AndroidPrefab.Tests.ps1 -AndroidSdk <sdk> -AndroidNdk <ndk> -JavaHome <jdk> -Gradle <gradle.bat> -CMake <cmake.exe> -Ninja <ninja.exe> -Feed <feed> -Abi arm64-v8a -SkipDevice
```

Скрипт копирует только независимый consumer, восстанавливает AAR из Maven, компилирует JNI и собирает APK, проверяет точный набор SO, отсутствие утечки private Helpers headers, отказы при static STL и конфликтующих вариантах. Код UDK/производитель не подключается через add_subdirectory к consumer. Сборки и логи остаются под !artifacts/Android/tests. SkipDevice означает BuildPassed-DeviceNotRun и не подтверждает работу на Android.

Для реального запуска уберите SkipDevice и передайте Serial из adb devices. Устанавливается только org.universaldevkit.packageconsumer; instrumentation вызывает настоящий C++ API через JNI и требует UDK_RESULT=PASS. Тестовое приложение остаётся на выбранном устройстве для диагностики. JNI здесь — тестовый мост; продуктовый Java/Kotlin API не добавлен.

Формат соответствует [Prefab](https://google.github.io/prefab/) и [Android native dependencies](https://developer.android.com/build/native-dependencies).