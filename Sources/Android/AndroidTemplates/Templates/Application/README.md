# {{Application}}

Android-приложение создано из AndroidTemplates UDK. AndroidBuildTools закреплён в android-build.psd1. Сборка: `build.ps1 build-android -Configuration Debug` либо Release. Секреты и локальные feeds задаёт ближайший Android.SharedProps.json.

AGP собирает native-часть через AAR/Prefab UDK {{UdkVersion}}: OpenGLESRenderer.Static, Diagnostic.Dynamic и c++_shared, NDK r27c/API 24+. Native-профиль пока Release, включая Debug APK. Код и библиотеки пакетов не копируются в проект. XAML генерирует отдельный UniversalDevKit.XamlCompiler.

Windows preview: `build.ps1 run-android-app-previewer -Configuration Debug` либо Release. Команда генерирует XAML, восстанавливает UniversalDevKit.AndroidAppPreviewer.PluginSDK версии {{UdkVersion}}, собирает PreviewPlugin и запускает WPF-превьювер. `-BuildOnly` выполняет только сборку плагина. Приложение UniversalDevKit.AndroidAppPreviewer всегда восстанавливается из PackagesFeed той же версии UDK. Windows CMake восстанавливает WPF-пакет и при сборке с -BuildOnly, чтобы запуск отладчика Visual Studio использовал пакет без локальных путей к EXE.