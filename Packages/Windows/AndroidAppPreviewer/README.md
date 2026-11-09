# AndroidAppPreviewer

Windows WPF-превьювер приложений из AndroidTemplates. Исходники: ThirdParty/AndroidAppPreviewer/AndroidAppPreviewer; проект: Projects/MsBuild/AndroidAppPreviewer/AndroidAppPreviewer.csproj. Поддерживает редактирование XAML, hot reload, инспекцию элементов, граф навигации и сценарии.

Сборка и упаковка: `Scripts/Packages/Windows/Pack.AndroidAppPreviewer.cmd`. NuGet UniversalDevKit.AndroidAppPreviewer использует корневую Version.json и содержит self-contained приложение в tools/win-x64 вместе со шрифтами и курсорами. Native SDK собирается отдельно; managed ABI подключён через ProjectReference из того же репозитория.

В потребителе: `build.ps1 run-android-app-previewer -Configuration Debug`. AndroidBuildTools всегда восстанавливает превьювер из PackagesFeed версии UdkVersion; внешние пути к EXE не используются. Debug/Release выбирают конфигурацию прикладного плагина, а WPF-приложение поставляется одним пакетом. Для прямого запуска: `AndroidAppPreviewer.exe --plugin <absolute-plugin.dll>`.