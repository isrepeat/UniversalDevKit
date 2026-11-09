//
// Описывает состав Gradle-проекта и репозитории для его зависимостей и плагинов.
//
pluginManagement {
    repositories {
        // Репозиторий Android Gradle Plugin.
        google()
        // Репозиторий Kotlin и остальных общих зависимостей.
        mavenCentral()
        // Репозиторий плагинов Gradle.
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    // Не разрешает модулям менять единый список репозиториев зависимостей.
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        // Репозиторий Android-зависимостей.
        google()
        // Репозиторий общих JVM-зависимостей.
        mavenCentral()
    }
}

// Имя корневого Gradle-проекта.
rootProject.name = "AndroidCoreSdk"

// Единственный модуль, формирующий публикуемую Android-библиотеку.
include(":androidcoresdk")