plugins {
    id("com.android.library") version "9.3.2"
}

layout.buildDirectory.set(file(providers.gradleProperty("udkBuildRoot").get()))

android {
    namespace = "org.universaldevkit.kotlinconsumer"
    compileSdk = 36
    defaultConfig { minSdk = 23 }
}

dependencies {
    implementation("com.isrepeat:androidappkit:1.0.19")
}