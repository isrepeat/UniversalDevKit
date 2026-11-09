# AndroidTemplates и AndroidBuildTools: создание и выпуск приложения

**Навигация:** [Главная](../README.md) → [Документация](README.md) → Android-приложения

Гайд описывает новый проект из AndroidTemplates, использующий пакеты UDK. Перевод существующих приложений не требуется: прикладную логику можно перенести в созданный проект позже.

## Содержание

- [Подготовка окружения и пакетов](#подготовка-окружения-и-пакетов)
- [Общая конфигурация](#общая-конфигурация)
- [Создание проекта](#создание-проекта)
- [Windows preview](#windows-preview)
- [Android APK](#android-apk)
- [Подпись и OAuth](#подпись-и-oauth)
- [Выпуск и Google Drive](#выпуск-и-google-drive)
- [Обновление инструментов](#обновление-инструментов)
- [Удаление и повторное создание](#удаление-и-повторное-создание)
- [Типичные ошибки](#типичные-ошибки)

## Подготовка окружения и пакетов

Рабочая проверенная конфигурация: Windows x64, Visual Studio 2026 с Desktop development with C++, CMake и Ninja; JDK 21; Android SDK Platform 36, Build Tools 36, Platform Tools; NDK r27c (`27.2.12479018`). Android-приложение использует API 24+ и arm64-v8a. Сборщик ищет Visual Studio через vswhere; Java — через JAVA_HOME/JDK_HOME и стандартные каталоги; SDK — через ANDROID_HOME/ANDROID_SDK_ROOT и стандартные каталоги.

Нужен `nuget.exe` в PATH. Если подготовка выполняется из checkout UDK, его закреплённую версию можно получить через `Scripts/Setup.cmd`; путь к подготовленному NuGet указан в [описании инструментов](Tools.md). SDK, NDK, JDK и Visual Studio устанавливаются отдельно. Готовый self-contained WPF-превьювер не требует отдельной установки .NET; сборка самого превьювера из UDK требует .NET SDK.

Источник PackagesFeed должен содержать обе структуры: NuGet-пакеты и Maven-репозиторий. Копирования только файлов .nupkg недостаточно для Android-сборки.

| Поставка | Для чего нужна |
|---|---|
| AndroidTemplates 1.0.0.34 | Генератор и шаблон приложения |
| AndroidBuildTools 1.0.63.31 | PowerShell, Gradle, CMake и ApplicationFramework |
| UniversalDevKit.XamlCompiler версии UDK | Генерация C++ из XAML на Windows |
| UniversalDevKit.AndroidAppPreviewer.PluginSDK версии UDK | Native SDK и Windows-библиотеки Debug/Release |
| UniversalDevKit.AndroidAppPreviewer версии UDK | WPF-приложение превьювера |
| com.isrepeat:androidappkit:1.0.19 и androidcoresdk:1.0.10 | Kotlin/AAR-часть; CoreSdk приходит транзитивно |
| org.universaldevkit:universaldevkit-openglesrenderer-static-release версии UDK | Android renderer, XamlRuntime и заголовки через AAR/Prefab |
| org.universaldevkit:universaldevkit-diagnostic-dynamic-release версии UDK | Общая Diagnostic SO через AAR/Prefab |

Это версии текущей поставки. Версия UDK читается из UdkVersion.json внутри AndroidTemplates и записывается в android-build.psd1; сейчас это 0.1.0. Генератор выбирает последнюю доступную версию AndroidBuildTools из feed и закрепляет её в проекте. NuGet-превьювер и его SDK восстанавливаются именно версии UdkVersion. Загрузчик XamlCompiler сейчас выбирает последнюю доступную версию своего пакета, поэтому в feed должна находиться совместимая версия.

В общей папке feed файлы .nupkg находятся рядом с Maven-каталогами `com/isrepeat/...` и `org/universaldevkit/...`, содержащими POM и AAR. Способы выпуска описаны в [Android AAR/Prefab](../Packages/Build/Android/README.md), [AndroidBuildTools](../Packages/Android/AndroidBuildTools/README.md), [AndroidTemplates](../Packages/Android/AndroidTemplates/README.md) и [универсальном инструменте выпуска](PackageComposition.md). Потребителю не нужен checkout UtilityHelpersLib или исходников превьювера.

## Общая конфигурация

До генерации создайте, например, `C:\WORK\Android\Projects\Android.SharedProps.json`:

```json
{
  "SchemaVersion": 1,
  "Paths": {
    "SecretsRoot": "../../Secrets/Android",
    "SigningProperties": "../../Secrets/Android/shared/signing.properties",
    "ApkUpdaterProjectRoot": "ApkUpdater",
    "DriveOAuthClientPath": "../../Secrets/android-drive-oauth.json",
    "DriveTokenPath": "../../Secrets/android-drive-token.json",
    "PackagesFeed": "../../Packages"
  },
  "Properties": {
    "GoogleCloudProject": "your-google-cloud-project"
  }
}
```

В этой раскладке секреты находятся в C:\WORK\Secrets\Android, а feed — в C:\WORK\Packages. Подставьте свои пути и Google Cloud project ID; пример не изменяет настройки машины.

Действующий контракт:

- SchemaVersion — целое число 1; Paths — объект с шестью обязательными непустыми строками из примера. Пока даже неиспользуемые настройки Drive и ApkUpdater должны присутствовать; сами файлы Drive нужны при соответствующей операции.
- Относительные пути считаются от каталога JSON. Абсолютные пути допустимы как локальная настройка машины.
- Поиск начинается от корня приложения, а при генерации — от будущего Destination, и продолжается вверх до корня диска. Ближайший JSON используется целиком; объединения с родительским нет.
- Повреждённый JSON или неподдерживаемая схема дают ошибку; поиск за повреждённым файлом не продолжается.
- SigningProperties при генерации должен лежать непосредственно в `<SecretsRoot>/shared`. Пароли и keystore находятся отдельно от JSON и исходников.
- Properties необязателен; GoogleCloudProject используется для ссылки на настройку OAuth.
- Настройки конкретного проекта находятся в android-build.psd1. Команды get-configuration-value и get-configuration-path читают его, а get-packages-feed возвращает общий PackagesFeed.
- Путей PreviewerDebugExecutablePath/PreviewerReleaseExecutablePath больше нет. Переменная UH_PACKAGES_FEED не является способом настройки текущего шаблона: feed задаётся через этот JSON.

NuGet.Config и стандартные Gradle properties пока не заменяют Android.SharedProps.json: текущие загрузчики явно передают PackagesFeed в инструменты.

## Создание проекта

Следующий пример устанавливает конкретную версию шаблонов и создаёт новый TestFooApp. Каталог приложения и `<SecretsRoot>/com.example.testfooapp` должны отсутствовать. Он не удаляет существующие проекты.

```powershell
$projectsRoot = 'C:\WORK\Android\Projects'
$configurationPath = Join-Path $projectsRoot 'Android.SharedProps.json'
$shared = Get-Content -LiteralPath $configurationPath -Raw | ConvertFrom-Json
$feed = if ([IO.Path]::IsPathRooted($shared.Paths.PackagesFeed)) {
    [IO.Path]::GetFullPath($shared.Paths.PackagesFeed)
} else {
    [IO.Path]::GetFullPath((Join-Path $projectsRoot $shared.Paths.PackagesFeed))
}
$templatesVersion = '1.0.0.34'
$bootstrap = Join-Path $env:TEMP ('AndroidTemplates-' + [Guid]::NewGuid().ToString('N'))

nuget.exe install AndroidTemplates -Version $templatesVersion -Source $feed -OutputDirectory $bootstrap -NonInteractive -ForceEnglishOutput
if ($LASTEXITCODE -ne 0) { throw 'AndroidTemplates restore failed.' }

$generator = Join-Path $bootstrap "AndroidTemplates.$templatesVersion\PowerShell\New-AndroidApplication.ps1"
& $generator -Name TestFooApp -PackageId com.example.testfooapp -Destination (Join-Path $projectsRoot 'TestFooApp') -ApkUpdaterProjectRoot ''
```

Пустой параметр ApkUpdaterProjectRoot отключает проверку внешнего Updater при генерации этого нового проекта. Если параметр не передан, генератор берёт путь из JSON и проверяет наличие build.ps1 в том проекте. Новый шаблон по умолчанию содержит `RequireUpdater = $false`: обычная сборка не собирает чужой ApkUpdater.

Генератор создаёт AndroidHost, Application, UI, PreviewPlugin, Android-модуль, Scripts, Tools/Gradle, build.ps1, android-build.psd1, CMake presets и launch.vs.json. Если общих signing-ключей ещё нет, создаются Debug/Release keystore и signing.properties в shared. Существующие общие ключи используются повторно. Также создаётся Google-OAuth-setup.md с package ID и SHA-1.

Если задан GoogleCloudProject, генератор может открыть страницу настройки OAuth в браузере. Это не загружает APK в Drive и не создаёт OAuth-клиентов автоматически.

После создания перейдите в проект:

```powershell
Set-Location 'C:\WORK\Android\Projects\TestFooApp'
.\build.ps1 restore
```

Restore восстанавливает закреплённый AndroidBuildTools и выводит путь к нему. Источник и общие настройки продолжают читаться из ближайшего JSON.

## Windows preview

```powershell
.\build.ps1 run-android-app-previewer -Configuration Debug
.\build.ps1 run-android-app-previewer -Configuration Release
```

Команда запускается для выбранной конфигурации: генерирует C++ из XAML, восстанавливает Preview SDK и WPF-приложение из NuGet, собирает прикладной плагин и запускает EXE из пакета с аргументом --plugin. Отдельно собирать или устанавливать AndroidAppPreviewer не нужно. Debug/Release выбирает конфигурацию плагина; WPF-приложение поставляется одним пакетом версии UDK.

Для сборки без открытия окна:

```powershell
.\build.ps1 run-android-app-previewer -Configuration Debug -BuildOnly
```

Windows CMake восстанавливает WPF-пакет также при BuildOnly: это подготавливает запуск отладчика Visual Studio. Откройте папку проекта в Visual Studio и выберите windows-x64-debug; launch.vs.json ссылается на EXE внутри проекта относительно workspaceRoot.

Артефакты по умолчанию:

- SDK: `Build/Preview/UniversalDevKit.AndroidAppPreviewer.PluginSDK.<UdkVersion>`; зависимости UDK восстанавливаются NuGet в соседние каталоги ID.VERSION.
- WPF: `Build/Preview/UniversalDevKit.AndroidAppPreviewer.<UdkVersion>/tools/win-x64`.
- CMake: `Build/Preview/cmake/Debug` или Release.
- Плагин: `Build/TestFooApp.PreviewPlugin/Build/Debug/x64/TestFooApp.PreviewPlugin/TestFooApp.PreviewPlugin.dll`; для Release меняется конфигурация в пути.

Есть также Scripts/run-android-app-previewer-debug.bat и run-android-app-previewer-release.bat. Превью поддерживает ввод, навигацию, инспекцию элементов и hot reload XAML. Подробнее об устройстве SDK — отдельном репозитории AndroidAppPreviewer.

## Android APK

Сборка без запуска превьювера и без загрузки в Drive:

```powershell
.\build.ps1 build-android -Configuration Debug
.\build.ps1 build-android -Configuration Release
```

Обычный build-android берёт VERSION_CODE_BASE и VERSION_NAME_BASE из version.properties и формирует имя версии как <VERSION_NAME_BASE>.0; счётчик выпуска он не увеличивает. Для сборки только native-части:

```powershell
.\build.ps1 build-android -Configuration Debug -NativeOnly
```

Gradle получает Kotlin AAR и native AAR/Prefab из PackagesFeed. C++ использует OpenGLESRenderer.Static, XamlRuntime, Diagnostic.Dynamic и c++_shared. Текущий Android native-профиль UDK — Release, включая Debug APK; Windows preview имеет отдельные Debug/Release библиотеки.

APK находится в `Build/TestFooApp.Android/outputs/apk/debug/TestFooApp.Android-debug.apk` либо в release с суффиксом -release.apk. Если adb доступен в PATH:

```powershell
adb install -r .\Build\TestFooApp.Android\outputs\apk\debug\TestFooApp.Android-debug.apk
```

Установка и запуск на устройстве — отдельная проверка: убедитесь в правильной отрисовке, вводе, обработке lifecycle и логировании. Успешная сборка APK сама по себе этого не подтверждает.

## Подпись и OAuth

Google-OAuth-setup.md содержит данные для двух Android OAuth-клиентов: Debug и Release. Создавайте их в Google Cloud только если приложению нужна соответствующая авторизация. Их package ID и SHA-1 должны совпадать с фактической подписью приложения.

Для загрузки в Google Drive используется отдельный Desktop OAuth client из DriveOAuthClientPath. DriveTokenPath создаётся после авторизации; его родительский каталог должен быть доступен для записи. Android OAuth-клиенты и Desktop client имеют разные назначения.

Сохраняйте резервную копию общих signing-ключей. При пересоздании проекта не удаляйте SecretsRoot/shared: новые ключи изменят подпись. JSON содержит пути; пароли и токены в него не помещаются.

ApkUpdater подключается отдельно. Только при осознанном включении RequireUpdater проверяйте внешний проект, его настройки, совпадение подписи и установку APK Updater на устройство. Генератор нового шаблона больше не собирает Debug/Release Updater автоматически.

## Выпуск и Google Drive

Сформировать версионированный APK локально:

```powershell
.\build.ps1 build-and-distribute -Destination Local -Configuration Release
```

Команда увеличивает версию, собирает APK и копирует его в `Build/distribution/TestFooApp-<version>-release.apk`. Для тестовой пересборки с сохранением версии используется KeepVersion именно этой команды:

```powershell
.\build.ps1 build-and-distribute -Destination Local -Configuration Debug -KeepVersion
```

После подготовки Desktop OAuth client загрузка в Drive запускается явно:

```powershell
.\build.ps1 build-and-distribute -Destination Drive -Configuration Debug
```

Путь в Drive задаётся секцией Drive в android-build.psd1. Также доступны Scripts/build-for-drive.debug.bat и build-for-drive.release.bat. Обычные build-android и Windows preview не публикуют APK.

## Обновление инструментов

```powershell
.\build.ps1 update-build-tools
```

Команда выбирает последнюю доступную версию AndroidBuildTools из feed и обновляет закреплённую версию в android-build.psd1. Чтобы выбрать конкретную:

```powershell
.\build.ps1 update-build-tools -BuildToolsVersion 1.0.63.31
```

Это обновляет инструменты, но не переносит новые файлы шаблона в существующий проект. UdkVersion согласует native AAR, Preview SDK и WPF-превьювер; при его изменении все соответствующие пакеты должны быть доступны в feed. Источники и шаблоны разрабатываются в UDK; приложение использует опубликованные пакеты.

## Удаление и повторное создание

Если проект больше не нужен, из его родительского каталога вызовите:

```powershell
$projectRoot = 'C:\WORK\Android\Projects\TestFooApp'
& "$projectRoot\Scripts\PowerShell\Remove-AndroidProject.ps1" -ProjectRoot $projectRoot
```

Скрипт запрашивает подтверждение и удаляет проект вместе с его отдельным каталогом секретов по PackageId; общая папка shared сохраняется. Для нового проекта используйте генератор заново. Если предыдущее создание прервано и отдельный каталог секретов остался без проекта, сначала проверьте его содержимое и назначение; генератор не перезаписывает его автоматически.

## Типичные ошибки

| Ошибка | Что проверить |
|---|---|
| Android.SharedProps.json not found | JSON находится в каталоге проекта или одном из его родителей; при генерации проверяется будущий Destination |
| Обязательное поле отсутствует | В Paths по-прежнему нужны шесть непустых строк, даже если Drive или ApkUpdater сейчас не используются |
| NuGet не находит закреплённый пакет | PackagesFeed, точную версию UdkVersion/AndroidBuildToolsVersion и наличие .nupkg |
| Gradle не находит com.isrepeat или org.universaldevkit | В том же feed нужна Maven-структура с POM/AAR, а не только NuGet |
| Visual Studio/CMake/JDK/SDK не найдены | Установленные компоненты и переменные JAVA_HOME, ANDROID_HOME; одного WPF-пакета недостаточно для сборки native-плагина |
| Ошибка длинного пути Windows | Выберите более короткий корень проекта; шаблон хранит SDK и Windows CMake в Build/Preview |
| Устройство отклоняет обновление APK | Package ID и подпись установленной версии; подписи Debug и Release различаются |
| Drive требует авторизацию | Desktop OAuth client, доступность каталога токена и настройки Drive; для обычной сборки загрузка не нужна |

Инструкция перенесена из Me/Documentation/AndroidBuild.md и обновлена по реализации AndroidTemplates и AndroidBuildTools в UDK.