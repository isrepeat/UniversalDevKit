//
// Собирает AndroidCoreSdk как AAR и публикует его в локальный Maven feed.
//
plugins {
    // Формирует Android-библиотеку и компилирует исходники Kotlin встроенными средствами AGP.
    id("com.android.library")
    // Добавляет задачи публикации Maven-пакета.
    id("maven-publish")
}

// Получает Maven group и версию из gradle.properties.
group = providers.gradleProperty("packageGroup").get()
version = providers.gradleProperty("packageVersion")
    .get()

android {
    // Пространство имён сгенерированных Android-ресурсов библиотеки.
    namespace = "com.isrepeat.androidcoresdk"

    // Версия Android API, с которой компилируется библиотека.
    compileSdk = providers.gradleProperty("androidCompileSdk").get().toInt()

    defaultConfig {
        // Минимальная версия Android API для потребляющего приложения.
        minSdk = providers.gradleProperty("androidMinSdk").get().toInt()
    }

    publishing {
        singleVariant("release") {
            // Публикует архив исходников вместе с AAR.
            withSourcesJar()
        }
    }
}

dependencies {
    // Публичные API SDK используют эти Android-библиотеки.
    api("androidx.activity:activity-ktx:1.8.0")
    api("androidx.lifecycle:lifecycle-runtime-ktx:2.6.1")
    api("com.google.android.gms:play-services-auth:21.3.0")
}

publishing {
    publications {
        register<MavenPublication>("release") {
            // Maven-координаты, по которым библиотека подключается в Android-проекте.
            groupId = project.group.toString()
            artifactId = "androidcoresdk"
            version = project.version.toString()

            afterEvaluate {
                // Добавляет release-вариант с AAR и архивом исходников в публикацию.
                from(components["release"])
            }
        }
    }

    repositories {
        maven {
            // Имя задачи публикации в общий локальный Maven feed.
            name = "AndroidPackagesFeed"
            // Каталог общего локального Maven feed для Android-пакетов.
            url = uri(providers.gradleProperty("androidPackagesFeedPath").get())
        }
    }
}