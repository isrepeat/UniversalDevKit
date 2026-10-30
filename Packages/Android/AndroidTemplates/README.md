# AndroidTemplates

Шаблон Android-приложения и команды его создания/удаления перенесены из UtilityHelpersLib. NuGet ID `AndroidTemplates`, версия `1.0.0.30`; версия задаётся Version.json без автоматического увеличения.

Сборка: `Scripts/Packages/Android/Pack.AndroidTemplates.cmd`. Внутри NuGet находятся PowerShell и template_app. После восстановления пакета вызовите `PowerShell/New-AndroidApplication.ps1 -Name MyApp -PackageId com.example.myapp -Destination <new-directory>`.

Генератор читает ближайший Android.SharedProps.json, закрепляет опубликованную версию AndroidBuildTools и версию UDK из поставки шаблона. Внешние signing/OAuth/Drive настройки сохраняют прежний контракт; секреты находятся вне исходников. Создание приложения может создавать локальные signing-ключи, но не публикует пакеты и не запускает OAuth-браузер автоматически.

Новый native-шаблон получает OpenGLESRenderer.Static и Diagnostic.Dynamic через Maven AAR/Prefab. Требуются опубликованные AAR UDK Release для arm64-v8a, AndroidAppKit 1.0.19/CoreSdk 1.0.10 и NuGet UniversalDevKit.XamlCompiler. Приложение использует NDK r27c, API 24+, c++_shared и Diagnostic. SDK/NDK/JDK устанавливаются отдельно.

После создания: `build.ps1 build-android -Configuration Debug`. Gradle получает локальные пути CMake/SDK от AndroidBuildTools; CMake не восстанавливает прежний XamlRuntime NuGet. Оба корневых native AAR содержат одну и ту же Diagnostic SO, поэтому шаблон выбирает один экземпляр конкретного файла. Их версии UDK закреплены одинаково, а граф проверяется Consumer.cmake.

PreviewPlugin и его команды сохранены как исходная заготовка; Windows preview явно отключён до отдельного переноса Preview SDK. Переход существующих рабочих приложений не входит в этот этап.


Внешний ApkUpdater перед сборкой проверяется только при RequireUpdater = $true в android-build.psd1; новый шаблон по умолчанию не собирает чужие проекты. Windows preset из исходного шаблона сохранён как заготовка, но preview ещё не подключён.