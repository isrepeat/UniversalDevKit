pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
    val restore = providers.exec {
        commandLine("powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-File", file("../../build.ps1").absolutePath, "restore")
    }
    val packageRoot = restore.standardOutput.asText.get().trim().lineSequence().last()
    System.setProperty("udk.androidBuildToolsRoot", packageRoot)
    includeBuild("$packageRoot/gradle")
}
plugins {
    id("com.isrepeat.android.settings")
}

rootProject.name = "{{Application}}"
include(":{{Application}}.Android")
project(":{{Application}}.Android").projectDir = file("../../{{Application}}.Android")

gradle.beforeProject { extensions.extraProperties["androidBuildToolsRoot"] = System.getProperty("udk.androidBuildToolsRoot") }