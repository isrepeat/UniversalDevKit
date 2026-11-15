//
// Defines the Gradle project and its dependency and plugin repositories.
//
pluginManagement {
    repositories {
        // Android Gradle Plugin repository.
        google()
        // Repository for Kotlin and other shared dependencies.
        mavenCentral()
        // Gradle plugin repository.
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    // Require modules to use the shared dependency repositories.
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        // Android dependency repository.
        google()
        // Shared JVM dependency repository.
        mavenCentral()
    }
}

// Root Gradle project name.
rootProject.name = "AndroidCoreSdk"

// The only module that produces the published Android library.
include(":androidcoresdk")