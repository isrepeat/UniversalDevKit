plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
    id("maven-publish")
}
android {
    namespace = "org.universaldevkit.testpackages.core"
    compileSdk = 36
    buildToolsVersion = "36.0.0"
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }
    defaultConfig { minSdk = 23 }
    publishing { singleVariant("release") { withSourcesJar() } }
}
kotlin { compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_1_8) } }
publishing {
    publications {
        register<MavenPublication>("release") {
            groupId = "org.universaldevkit.testpackages"
            artifactId = "core"
            version = "1.0.0"
            afterEvaluate { from(components["release"]) }
        }
    }
    repositories { maven { name = "PackageDelivery"; url = uri(providers.gradleProperty("testPackagesFeed").get()) } }
}