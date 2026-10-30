package com.isrepeat.build


class AndroidSettingsPlugin implements org.gradle.api.Plugin<org.gradle.api.initialization.Settings> {
    void apply(org.gradle.api.initialization.Settings settings) {
        // Ближайший общий JSON задаёт источник библиотек так же, как PowerShell-сборка.
        def directory = settings.settingsDir
        def sharedFile = null
        while (directory != null && sharedFile == null) {
            def candidate = new java.io.File(directory, 'Android.SharedProps.json')
            if (candidate.isFile()) { sharedFile = candidate }
            directory = directory.parentFile
        }
        if (sharedFile == null) { throw new org.gradle.api.GradleException('Android.SharedProps.json was not found.') }
        def shared = new groovy.json.JsonSlurper().parseText(settings.providers.fileContents(settings.layout.settingsDirectory.file(sharedFile.absolutePath)).asText.get())
        if (shared.SchemaVersion != 1 || !shared.Paths?.PackagesFeed) {
            throw new org.gradle.api.GradleException('Shared SchemaVersion 1 and Paths.PackagesFeed are required.')
        }
        def feed = new java.io.File(shared.Paths.PackagesFeed.toString())
        if (!feed.isAbsolute()) { feed = new java.io.File(sharedFile.parentFile, shared.Paths.PackagesFeed.toString()) }
        settings.pluginManagement.repositories {
            google()
            mavenCentral()
            gradlePluginPortal()
        }
        settings.dependencyResolutionManagement {
            repositoriesMode.set(org.gradle.api.initialization.resolve.RepositoriesMode.FAIL_ON_PROJECT_REPOS)
            repositories {
                maven {
                    url = settings.providers.gradleProperty('androidMavenSource')
                        .orElse(settings.providers.environmentVariable('ANDROID_MAVEN_SOURCE'))
                        .orElse(feed.absolutePath).get()
                }
                google()
                mavenCentral()
            }
        }
    }
}