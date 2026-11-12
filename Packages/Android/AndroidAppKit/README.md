# AndroidAppKit

Kotlin AAR, перенесённый из UtilityHelpersLib. Публичные Kotlin packages и Maven-координаты сохранены.

Координаты: `com.isrepeat:androidappkit:1.0.19`. Минимальный Android API — 23, compileSdk — 36. Исходники находятся в Sources/Android/AndroidAppKit/src/main; Gradle-проект — в Projects/Gradle/Library/AndroidAppKit; описание доставки — здесь, в Delivery/Android.

Сборка и публикация в новый локальный Maven feed:

```powershell
./Scripts/Packages/Android/Pack.AndroidAppKit.cmd -OutputDirectory C:/Temp/UdkAndroidFeed
```

Перед AndroidAppKit всегда запускаются сборка и локальная публикация AndroidCoreSdk 1.0.10. Gradle самостоятельно переиспользует актуальные результаты задач; наличие пакета в feed не отменяет проверку исходников. Зависимость CoreSdk закреплена в gradle.properties. AndroidAppKit запускается с --refresh-dependencies, чтобы получить актуальный CoreSdk после повторной локальной публикации той же версии; кеш задач сборки при этом сохраняется.

Версия задаётся полем `version` в `Package.json` и не меняется при сборке. Повторная сборка обновляет целевой пакет. JDK 21 и Android SDK определяются общим resolver UDK; NDK не требуется. Артефакты и Gradle project cache находятся в !artifacts/packages/maven/build-gradle. Параметры AndroidSdk, JavaHome и Gradle позволяют явно выбрать инструменты.

Прямая команда без паузы: Packages/Build/Build.ps1 -PackagePath Packages/Android/AndroidAppKit/Package.json -Delivery Android -OutputDirectory <feed>.

XamlRuntime и preview SDK в этот перенос не входят.