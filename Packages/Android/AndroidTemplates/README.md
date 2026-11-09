# AndroidTemplates

Полный цикл создания приложения, настройки и выпуска: [гайд Android-приложений](../../../Docs/AndroidBuild.md).

Шаблон Android-приложения и команды его создания/удаления перенесены из UtilityHelpersLib. NuGet ID `AndroidTemplates`, версия `1.0.0.34`; версия задаётся Version.json без автоматического увеличения.

Сборка: `Scripts/Packages/Android/Pack.AndroidTemplates.cmd`. Исходники команд и шаблона находятся в Sources/Android/AndroidTemplates/PowerShell и Sources/Android/AndroidTemplates/Templates/Application. Delivery.json собирает из них прежние PowerShell и template_app внутри NuGet. После восстановления пакета вызовите `PowerShell/New-AndroidApplication.ps1 -Name MyApp -PackageId com.example.myapp -Destination <new-directory>`.

Генератор читает ближайший Android.SharedProps.json, закрепляет опубликованную версию AndroidBuildTools и версию UDK из поставки шаблона. Внешние signing/OAuth/Drive настройки сохраняют прежний контракт; секреты находятся вне исходников. Создание приложения может создавать локальные signing-ключи, но не публикует пакеты и не запускает OAuth-браузер автоматически.

Новый native-шаблон получает OpenGLESRenderer.Static и Diagnostic.Dynamic через Maven AAR/Prefab. Требуются опубликованные AAR UDK Release для arm64-v8a, AndroidAppKit 1.0.19/CoreSdk 1.0.10 и NuGet UniversalDevKit.XamlCompiler. Приложение использует NDK r27c, API 24+, c++_shared и Diagnostic. SDK/NDK/JDK устанавливаются отдельно.

После создания: `build.ps1 build-android -Configuration Debug`. Gradle получает локальные пути CMake/SDK от AndroidBuildTools; CMake не восстанавливает прежний XamlRuntime NuGet. Оба корневых native AAR содержат одну и ту же Diagnostic SO, поэтому шаблон выбирает один экземпляр конкретного файла. Их версии UDK закреплены одинаково, а граф проверяется Consumer.cmake.

Windows preview подключён к UDK: `build.ps1 run-android-app-previewer -Configuration Debug` либо Release; `-BuildOnly` собирает только DLL. Из PackagesFeed восстанавливаются UniversalDevKit.AndroidAppPreviewer.PluginSDK и UniversalDevKit.AndroidAppPreviewer версии UdkVersion. SDK объявляет зависимости на отдельные NuGet XamlRuntime, OpenGLESRenderer и Diagnostic; Helpers восстанавливается транзитивно, ANGLE поставляется OpenGLESRenderer. Сам SDK не содержит копий native-библиотек. Старые UtilityHelpersLib и XamlRuntime NuGet не требуются. Пути к EXE в Android.SharedProps.json и параметры выбора внешнего превьювера не используются. Windows CMake восстанавливает WPF-пакет также для запуска отладчика Visual Studio.


Внешний ApkUpdater перед сборкой проверяется только при RequireUpdater = $true в android-build.psd1; новый шаблон по умолчанию не собирает чужие проекты. Windows preset поддерживает сборку PreviewPlugin из Visual Studio. Перевод существующих приложений не требуется: прикладную логику можно переносить в новый проект из AndroidTemplates.