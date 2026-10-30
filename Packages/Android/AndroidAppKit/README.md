# AndroidAppKit

Kotlin AAR, перенесённый из UtilityHelpersLib. Публичные Kotlin packages и Maven-координаты сохранены.

Координаты: `com.isrepeat:androidappkit:1.0.19`. Минимальный Android API — 23, compileSdk — 36. Исходники находятся в Sources/src/main; Gradle-проект — в Projects/Gradle; описание доставки — в Delivery/Android.

Сборка и публикация в новый локальный Maven feed:

```powershell
./Scripts/Packages/Android/Pack.AndroidAppKit.cmd -OutputDirectory C:/Temp/UdkAndroidFeed
```

Сначала собирается AndroidCoreSdk 1.0.10, затем AndroidAppKit. Зависимость CoreSdk закреплена в gradle.properties; уже имеющаяся в feed версия CoreSdk используется повторно.

Версия задаётся packageVersion в Projects/Gradle/gradle.properties и не меняется при сборке. Повторная сборка обновляет целевой пакет. JDK 21 и Android SDK определяются общим resolver UDK; NDK не требуется. Артефакты и Gradle project cache находятся в !artifacts/packages/maven/build-gradle. Параметры AndroidSdk, JavaHome и Gradle позволяют явно выбрать инструменты.

Прямая команда без паузы: Packages/Build/Android/BuildKotlin.ps1 -Package AndroidAppKit -OutputDirectory <feed>.

XamlRuntime и preview SDK в этот перенос не входят.