pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement {
    repositories {
        maven { url = uri(providers.gradleProperty("udkFeed").get()) }
        google()
        mavenCentral()
    }
}
rootProject.name = "UniversalDevKitAndroidConsumer"
include(":app")