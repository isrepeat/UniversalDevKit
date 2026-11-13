//
// Gradle plugin versions shared by all package modules.
//
plugins {
    // Enable Android AAR builds.
    id("com.android.library") version "9.3.2" apply false
}

val artifactRoot = providers.gradleProperty("udkBuildRoot").get()
layout.buildDirectory.set(file("$artifactRoot/root"))
subprojects {
    layout.buildDirectory.set(file("$artifactRoot/${project.name}"))
}