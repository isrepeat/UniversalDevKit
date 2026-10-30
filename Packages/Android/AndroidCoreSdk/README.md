# AndroidCoreSdk

Kotlin AAR, перенесённый из UtilityHelpersLib. Публичные Kotlin packages и Maven-координаты сохранены.

Координаты: `com.isrepeat:androidcoresdk:1.0.10`. Минимальный Android API — 23, compileSdk — 36. Исходники находятся в Sources/src/main; Gradle-проект — в Projects/Gradle; описание доставки — в Delivery/Android.

Сборка и публикация в новый локальный Maven feed:

```powershell
./Scripts/Packages/Android/Pack.AndroidCoreSdk.cmd -OutputDirectory C:/Temp/UdkAndroidFeed
```

Публикуются release AAR, sources JAR, POM и Gradle Module Metadata.

Версия задаётся packageVersion в Projects/Gradle/gradle.properties и не меняется при сборке. Существующая версия целевого пакета не перезаписывается. JDK 21 и Android SDK определяются общим resolver UDK; NDK не требуется. Артефакты и Gradle project cache находятся в !artifacts/Android/gradle. Параметры AndroidSdk, JavaHome и Gradle позволяют явно выбрать инструменты.

Прямая команда без паузы: Packages/Build/Android/BuildKotlin.ps1 -Package AndroidCoreSdk -OutputDirectory <feed>.

XamlRuntime и preview SDK в этот перенос не входят.