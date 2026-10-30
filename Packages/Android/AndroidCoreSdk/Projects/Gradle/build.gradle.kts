//
// Задаёт версии Gradle-плагинов, используемых всеми модулями пакета.
//
plugins {
    // Поддержка сборки Android-библиотеки в формате AAR.
    id("com.android.library") version "9.3.2" apply false
}

val artifactRoot = providers.gradleProperty("udkBuildRoot").get()
layout.buildDirectory.set(file("$artifactRoot/root"))
subprojects {
    layout.buildDirectory.set(file("$artifactRoot/${project.name}"))
}