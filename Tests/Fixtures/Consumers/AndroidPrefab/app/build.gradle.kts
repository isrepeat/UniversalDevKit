plugins { id("com.android.application") }
val component = providers.gradleProperty("udkComponent").getOrElse("DiagnosticTest")
val mode = providers.gradleProperty("udkMode").getOrElse("Dynamic")
android {
    namespace = "org.universaldevkit.packageconsumer"
    compileSdk = 36
    buildToolsVersion = "36.0.0"
    ndkPath = providers.gradleProperty("udkNdk").get()
    ndkVersion = providers.gradleProperty("udkNdkVersion").getOrElse("27.2.12479018")
    defaultConfig {
        applicationId = "org.universaldevkit.packageconsumer"
        minSdk = 24
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
        ndk { abiFilters += providers.gradleProperty("udkAbi").getOrElse("arm64-v8a") }
        externalNativeBuild {
            cmake { arguments += listOf("-DANDROID_STL=${providers.gradleProperty("udkStl").getOrElse("c++_shared")}", "-DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON", "-DCMAKE_CXX_COMPILER_ARG1=--driver-mode=g++", "-DUDK_COMPONENT=$component", "-DUDK_MODE=$mode", "-DUDK_CONFLICT=${providers.gradleProperty("udkConflict").getOrElse("OFF")}") }
        }
    }
    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("debug")
            externalNativeBuild { cmake { arguments += "-DCMAKE_BUILD_TYPE=Release" } }
        }
    }
    buildFeatures { prefab = true }
    externalNativeBuild { cmake { path = file("src/main/cpp/CMakeLists.txt") } }
}
dependencies {
    implementation("org.universaldevkit:universaldevkit-${component.lowercase()}-${mode.lowercase()}-release:${providers.gradleProperty("udkVersion").get()}")
    if (providers.gradleProperty("udkConflict").isPresent) {
        implementation("org.universaldevkit:universaldevkit-heleprstest-dynamic-release:${providers.gradleProperty("udkVersion").get()}")
    }
}