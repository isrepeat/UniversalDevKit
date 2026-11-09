# Структура исходников

Кроссплатформенные компоненты сохраняют стабильные корни Includes/<имя> и Sources/<имя>. Платформенные компоненты используют симметричные Includes/<платформа>/<имя> и Sources/<платформа>/<имя>. Категория соответствует назначению компонента, отражённому в Packages: CrossPlatform не добавляется в пути исходников, Android и Windows добавляются.

- Includes — только публичные C++ заголовки и публичная шаблонная реализация.
- Sources — реализация и внутренние заголовки, Kotlin-код, ресурсы, поставляемые потребителю скрипты и шаблоны.
- Projects/<система>/<компонент> — проекты сборки Cmake, MsBuild и Gradle. Каталоги проекта создаваемого приложения остаются частью шаблона.
- Packages — описание выпуска, версии, delivery-манифесты, nuspec и интеграция доставки.
- Scripts — обслуживание репозитория: подготовка инструментов, точки входа сборки и проверки.

## Публичные пути

Общий компонент: Includes/XamlRuntime/UniversalDevKit/XamlRuntime/RenderEngine.h и Sources/XamlRuntime. Публичный include и namespace сохраняются: UniversalDevKit/XamlRuntime/RenderEngine.h, universaldevkit::xamlruntime.

Платформенный компонент: Includes/Android/AndroidBuildTools/UniversalDevKit/Android/AndroidBuildTools/ApplicationFramework/InputDispatcher.h и Sources/Android/AndroidBuildTools/ApplicationFramework. Публичный include: UniversalDevKit/Android/AndroidBuildTools/ApplicationFramework/InputDispatcher.h. Namespace: universaldevkit::android::androidbuildtools::applicationframework.

Потребителю передаётся корень конкретного компонента Includes/Android/AndroidBuildTools, а не общий Includes или Sources. Платформенные варианты внутри общего компонента, например Sources/Diagnostic/platform/android, сохраняют общий публичный API Diagnostic без платформенного сегмента.

## Инструменты и шаблоны

Kotlin-код AndroidCoreSdk и AndroidAppKit находится в Sources/Android/<имя>/src/main. Projects/Gradle/<имя> подключает его через sourceSets. Kotlin packages com.isrepeat и Maven-координаты сохраняются.

Потребительские команды находятся в Sources/Android/AndroidBuildTools/PowerShell, CMake-модули — в Cmake, исходники Gradle-плагинов — в Gradle. ApplicationFramework использует публичные заголовки из Includes/Android/AndroidBuildTools и проект Projects/Cmake/AndroidBuildTools/ApplicationFramework.

Команды создания приложения находятся в Sources/Android/AndroidTemplates/PowerShell, заготовки — в Sources/Android/AndroidTemplates/Templates/Application. Это исходное содержимое компонента, а не служебные скрипты репозитория.

Host-инструмент XamlCompiler находится в Sources/Windows/XamlCompiler. Его внутренний namespace — universaldevkit::windows::xamlcompiler; main остаётся глобальной точкой входа. Генерируемый C++ код остаётся кроссплатформенным и использует прежние namespace XamlRuntime.

Content delivery задаёт source относительно корня репозитория и target внутри пакета. AndroidBuildTools поставляет публичные заголовки в build/native/include/UniversalDevKit/Android/AndroidBuildTools, а реализацию и CMake-файл framework — в build/native/Android/AndroidBuildTools/ApplicationFramework. Структура PowerShell/template_app в AndroidTemplates сохраняется. Каталог Products не используется.