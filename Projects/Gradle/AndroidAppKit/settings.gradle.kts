pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        maven { url = uri(providers.gradleProperty("androidPackagesFeedPath").get()) }
        google()
        mavenCentral()
    }
}

rootProject.name = "AndroidAppKit"
include(":androidappkit")