# {{Application}}

Android-приложение создано из AndroidTemplates UDK. AndroidBuildTools закреплён в android-build.psd1. Сборка: `build.ps1 build-android -Configuration Debug` либо Release. Секреты и локальные feeds задаёт ближайший Android.SharedProps.json.

AGP собирает native-часть через AAR/Prefab UDK {{UdkVersion}}: OpenGLESRenderer.Static, Diagnostic.Dynamic и c++_shared, NDK r27c/API 24+. Native-профиль пока Release, включая Debug APK. Код и библиотеки пакетов не копируются в проект. XAML генерирует отдельный UniversalDevKit.XamlCompiler.

Preview SDK подключается отдельным этапом. Не запускайте Windows preview из этой заготовки до завершения его переноса.