pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement {
    repositories {
        maven { url = uri(providers.gradleProperty("testPackagesFeed").get()) }
        google()
        mavenCentral()
    }
}
rootProject.name = "UdkPackagePackageDelivery"
if (providers.gradleProperty("consumerOnly").isPresent) {
    include(":consumer")
} else {
    include(":core", ":appkit")
}