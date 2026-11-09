# Проверка Windows preview

Создайте приложение из упакованного AndroidTemplates, затем выполните `build.ps1 run-android-app-previewer -Configuration Debug -BuildOnly` и аналогично Release. PackagesFeed должен содержать AndroidBuildTools, UniversalDevKit.XamlCompiler и оба пакета превью версии UdkVersion. Пути к EXE превьювера не задаются: WPF-приложение восстанавливается из NuGet при настройке Windows CMake.

Соберите этот CMake-проект в !artifacts/tests/PreviewerSmoke с Visual Studio x64. Запустите `PreviewerSmoke.exe <absolute-template-plugin.dll> <absolute-Roboto-Regular.ttf> urn:myapp:xaml`. Последний аргумент — namespace приложения из XAML. Проверяются согласование ABI, прикладная сессия, переходы графа, реальные пиксели ANGLE, ввод, resize, отклонение ошибочного XAML и успешный hot reload. Шрифт находится в ThirdParty/AndroidAppPreviewer/AndroidAppPreviewer/Resources/Fonts. Успех — строка PASS и код 0.

Проверка интерфейса: запустите превьювер с --plugin, откройте страницу, измените XAML и проверьте hot reload. Android ARM64 APK проверяет независимость прикладной сборки от Windows SDK; поведение на устройстве проверяется отдельно.