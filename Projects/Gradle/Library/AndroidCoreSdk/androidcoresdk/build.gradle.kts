import groovy.json.JsonSlurper

//
// Build AndroidCoreSdk as an AAR and publish it to the local Maven feed.
//
plugins {
    // Build the Android library and compile Kotlin through AGP.
    id("com.android.library")
    // Add Maven publishing tasks.
    id("maven-publish")
}

// Read the direct build version from the package description.
group = providers.gradleProperty("packageGroup").get()
version = providers.gradleProperty("packageVersion").orElse(providers.provider {
    val manifest = rootProject.file("../../../../Packages/Android/AndroidCoreSdk/Package.json")
    (JsonSlurper().parse(manifest) as Map<*, *>)["version"] as String
}).get()

extensions.configure<com.android.build.api.dsl.LibraryExtension>("android") {
    sourceSets.getByName("main") {
        manifest.srcFile("../../../../../Sources/Android/AndroidCoreSdk/src/main/AndroidManifest.xml")
        java.setSrcDirs(listOf("../../../../../Sources/Android/AndroidCoreSdk/src/main/java"))
        kotlin.setSrcDirs(listOf("../../../../../Sources/Android/AndroidCoreSdk/src/main/kotlin"))
    }
    // Namespace for the generated Android library resources.
    namespace = "com.isrepeat.androidcoresdk"

    // Android API level used to compile the library.
    compileSdk = providers.gradleProperty("androidCompileSdk").get().toInt()

    defaultConfig {
        // Minimum Android API level for consuming apps.
        minSdk = providers.gradleProperty("androidMinSdk").get().toInt()
    }

    publishing {
        singleVariant("release") {
            // Publish the sources archive alongside the AAR.
            withSourcesJar()
        }
    }
}

dependencies {
    // These Android libraries appear in the public SDK APIs.
    api("androidx.activity:activity-ktx:1.8.0")
    api("androidx.lifecycle:lifecycle-runtime-ktx:2.6.1")
    api("com.google.android.gms:play-services-auth:21.3.0")
}

publishing {
    publications {
        register<MavenPublication>("release") {
            // Maven coordinates used by Android consumers.
            groupId = project.group.toString()
            artifactId = "androidcoresdk"
            version = project.version.toString()

            afterEvaluate {
                // Publish the release AAR and sources archive.
                from(components["release"])
            }
        }
    }

    repositories {
        maven {
            // Task name for publication to the shared local Maven feed.
            name = "AndroidPackagesFeed"
            // Shared local Maven feed for Android packages.
            url = uri(providers.gradleProperty("udkPublicationFeedPath").orElse(providers.gradleProperty("androidPackagesFeedPath")).get())
        }
    }
}