plugins {
    id("com.isrepeat.android.application")
}
android {
    namespace = "{{PackageId}}"
    ndkVersion = "27.2.12479018"
    ndkPath = providers.gradleProperty("androidNdk").orElse(providers.environmentVariable("ANDROID_NDK_HOME")).orNull
    defaultConfig {
        applicationId = "{{PackageId}}"
        minSdk = 24
        externalNativeBuild.cmake.arguments += listOf(
            "-DANDROID_STL=c++_shared",
            "-DCMAKE_CXX_COMPILER_ARG1=--driver-mode=g++",
            "-DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON",
            "-DANDROID_BUILD_TOOLS_ROOT=${System.getProperty("udk.androidBuildToolsRoot")}"
        )
    }
    buildFeatures.prefab = true
    externalNativeBuild.cmake {
        path = file("../CMakeLists.txt")
    }
    buildTypes {
        getByName("debug") {
            externalNativeBuild.cmake.arguments += "-DCMAKE_BUILD_TYPE=Release"
            manifestPlaceholders["appTitle"] = "{{Application}} ${defaultConfig.versionName} (debug)"
        }
        getByName("release") {
            externalNativeBuild.cmake.arguments += "-DCMAKE_BUILD_TYPE=Release"
            manifestPlaceholders["appTitle"] = "{{Application}}"
        }
    }
    // Оба AAR доставляют один и тот же Diagnostic.Dynamic одной версии UDK.
    packaging.jniLibs.pickFirsts += "lib/arm64-v8a/libuniversaldevkit_diagnostic_dynamic.so"
}
dependencies {
    implementation("com.isrepeat:androidappkit:1.0.19")
    implementation("org.universaldevkit:universaldevkit-openglesrenderer-static-release:{{UdkVersion}}")
    implementation("org.universaldevkit:universaldevkit-diagnostic-dynamic-release:{{UdkVersion}}")
    implementation("com.google.android.gms:play-services-auth:21.3.0")
}