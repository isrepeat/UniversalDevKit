import groovy.json.JsonSlurper

plugins {
    id("com.android.library")
    id("maven-publish")
}

group = providers.gradleProperty("packageGroup").get()
version = providers.gradleProperty("packageVersion").orElse(providers.provider {
    val manifest = rootProject.file("../../../Packages/Android/AndroidAppKit/Package.json")
    (JsonSlurper().parse(manifest) as Map<*, *>)["version"] as String
}).get()

extensions.configure<com.android.build.api.dsl.LibraryExtension>("android") {
    sourceSets.getByName("main") {
        manifest.srcFile("../../../../Sources/Android/AndroidAppKit/src/main/AndroidManifest.xml")
        java.setSrcDirs(listOf("../../../../Sources/Android/AndroidAppKit/src/main/java"))
        kotlin.setSrcDirs(listOf("../../../../Sources/Android/AndroidAppKit/src/main/kotlin"))
    }
    namespace = "com.isrepeat.androidappkit"
    compileSdk = providers.gradleProperty("androidCompileSdk").get().toInt()

    defaultConfig {
        minSdk = providers.gradleProperty("androidMinSdk").get().toInt()
    }

    publishing {
        singleVariant("release") {
            withSourcesJar()
        }
    }
}

dependencies {
    api("com.isrepeat:androidcoresdk:${providers.gradleProperty("androidCoreSdkVersion").get()}")
}

publishing {
    publications {
        register<MavenPublication>("release") {
            groupId = project.group.toString()
            artifactId = "androidappkit"
            version = project.version.toString()

            afterEvaluate {
                from(components["release"])
            }
        }
    }

    repositories {
        maven {
            name = "AndroidPackagesFeed"
            url = uri(providers.gradleProperty("udkPublicationFeedPath").orElse(providers.gradleProperty("androidPackagesFeedPath")).get())
        }
    }
}