package com.isrepeat.build

class AndroidApplicationPlugin implements org.gradle.api.Plugin<org.gradle.api.Project> {
    void apply(org.gradle.api.Project project) {
        // Apply the Android plugin and write outputs outside the source directories.
        // The Gradle root is Tools/Gradle, so go up two levels.
        project.pluginManager.apply('com.android.application')
        def repositoryRoot = project.rootProject.projectDir.parentFile.parentFile
        project.layout.buildDirectory.set(new java.io.File(repositoryRoot, "Build/${project.name}"))

        // An explicitly supplied version overrides the project's base version.
        // Using providers lets Gradle track the file in the configuration cache.
        def versionFile = project.providers.gradleProperty('appVersionFile')
            .map { new java.io.File(repositoryRoot, it) }.getOrElse(new java.io.File(repositoryRoot, 'version.properties'))
        def versions = new java.util.Properties()
        if (versionFile.isFile()) {
            versions.load(new java.io.StringReader(project.providers.fileContents(project.layout.projectDirectory.file(versionFile.absolutePath)).asText.get()))
        }
        def code = project.providers.gradleProperty('appVersionCode').orNull
        def name = project.providers.gradleProperty('appVersionName').orNull
        if ((code == null) != (name == null)) {
            throw new org.gradle.api.GradleException('appVersionCode and appVersionName must be specified together.')
        }
        code = code ?: versions.getProperty('VERSION_CODE_BASE')
        name = name ?: versions.getProperty('VERSION_NAME_BASE')?.concat('.0')
        if (code == null || name == null || !(code ==~ /[1-9][0-9]*/) || code.toLong() > 2100000000L) {
            throw new org.gradle.api.GradleException('Provide valid appVersionCode/appVersionName or VERSION_CODE_BASE/VERSION_NAME_BASE.')
        }
        // The Gradle property overrides the environment variable, with JSON as fallback.
        def signingPath = project.providers.gradleProperty('androidSigningProperties')
            .orElse(project.providers.environmentVariable('ANDROID_SIGNING_PROPERTIES')).orNull
        // Find the nearest JSON above the app root without merging parent files.
        def androidSharedPropsDirectory = repositoryRoot
        def androidSharedPropsFile = null
        while (androidSharedPropsDirectory != null) {
            def candidate = new java.io.File(androidSharedPropsDirectory, 'Android.SharedProps.json')
            if (candidate.isFile()) {
                androidSharedPropsFile = candidate
                break
            }
            androidSharedPropsDirectory = androidSharedPropsDirectory.parentFile
        }
        if (androidSharedPropsFile == null) {
            throw new org.gradle.api.GradleException("Android.SharedProps.json was not found above ${repositoryRoot}.")
        }
        // Validate the contract version and required paths before configuring APK signing.
        def androidSharedPropsText = project.providers.fileContents(project.layout.projectDirectory.file(androidSharedPropsFile.absolutePath)).asText.get()
        def androidSharedProps = new groovy.json.JsonSlurper().parseText(androidSharedPropsText)
        if (!(androidSharedProps instanceof java.util.Map) || androidSharedProps.SchemaVersion != 1 || !(androidSharedProps.Paths?.SigningProperties instanceof java.lang.String) || androidSharedProps.Paths.SigningProperties.trim().isEmpty()) {
            throw new org.gradle.api.GradleException("Invalid Android.SharedProps.json contract: ${androidSharedPropsFile}.")
        }
        ['SecretsRoot', 'SigningProperties', 'DriveOAuthClientPath', 'DriveTokenPath', 'PackagesFeed'].each { key ->
            if (!(androidSharedProps.Paths[key] instanceof java.lang.String) || androidSharedProps.Paths[key].trim().isEmpty()) {
                throw new org.gradle.api.GradleException("Android.SharedProps.json must define Paths.${key}: ${androidSharedPropsFile}.")
            }
        }
        if (signingPath == null) {
            // Resolve relative paths from the JSON directory.
            def sharedSigning = new java.io.File(androidSharedProps.Paths.SigningProperties)
            signingPath = (sharedSigning.isAbsolute() ? sharedSigning : new java.io.File(androidSharedPropsFile.parentFile, androidSharedProps.Paths.SigningProperties)).absolutePath
        }
        if (!project.file(signingPath).isFile()) {
            throw new org.gradle.api.GradleException("Shared signing properties were not found: ${signingPath}.")
        }
        // Read passwords and the keystore from a separate file outside the shared JSON.
        def signing = new java.util.Properties()
        if (signingPath != null && project.file(signingPath).isFile()) {
            def signingFile = project.layout.projectDirectory.file(project.file(signingPath).absolutePath)
            signing.load(new java.io.StringReader(project.providers.fileContents(signingFile).asText.get()))
            ['storeFile', 'storePassword', 'keyAlias', 'keyPassword'].each {
                if (!signing.getProperty(it)) {
                    throw new org.gradle.api.GradleException("Signing properties must define ${it}.")
                }
            }
        }
        // Set the shared SDK versions, app version, and only supported ABI.
        project.extensions.configure(com.android.build.api.dsl.ApplicationExtension) { android ->
            android.compileSdk = 36
            android.defaultConfig {
                minSdk = 24
                targetSdk = 36
                versionCode = code.toInteger()
                versionName = name
                ndk.abiFilters.add('arm64-v8a')
            }
            android.compileOptions {
                sourceCompatibility = org.gradle.api.JavaVersion.VERSION_11
                targetCompatibility = org.gradle.api.JavaVersion.VERSION_11
            }
            // In AGP 9, built-in Kotlin inherits the JVM target from compileOptions.
            android.buildTypes.getByName('release').optimization.enable = false
            if (!signing.isEmpty()) {
                // All apps and the updater share the same Release key.
                def releaseSigning = android.signingConfigs.maybeCreate('release')
                releaseSigning.storeFile = project.file(signing.getProperty('storeFile'))
                releaseSigning.storePassword = signing.getProperty('storePassword')
                releaseSigning.keyAlias = signing.getProperty('keyAlias')
                releaseSigning.keyPassword = signing.getProperty('keyPassword')
                android.buildTypes.getByName('release').signingConfig = releaseSigning

                def debugSigningKeys = ['debugStoreFile', 'debugStorePassword', 'debugKeyAlias', 'debugKeyPassword']
                if (debugSigningKeys.every { signing.getProperty(it) }) {
                    // Debug uses a separate key from the same settings file.
                    def debugSigning = android.signingConfigs.maybeCreate('debug')
                    debugSigning.storeFile = project.file(signing.getProperty('debugStoreFile'))
                    debugSigning.storePassword = signing.getProperty('debugStorePassword')
                    debugSigning.keyAlias = signing.getProperty('debugKeyAlias')
                    debugSigning.keyPassword = signing.getProperty('debugKeyPassword')
                    android.buildTypes.getByName('debug').signingConfig = debugSigning
                }
            }
            // Validate the Release keystore after configuring the DSL and before building.
            def verifySigning = project.tasks.register('verifyReleaseSigning', VerifyReleaseSigning)
            project.extensions.getByName('androidComponents').finalizeDsl { finalized ->
                verifySigning.configure {
                    configured.set(finalized.buildTypes.getByName('release').signingConfig?.storeFile?.isFile() == true)
                }
            }
            project.tasks.matching { it.name == 'preReleaseBuild' }.configureEach {
                dependsOn(verifySigning)
            }
            // Include the CMake output directory in the APK when the native library already exists.
            def nativeDirectory = project.providers.gradleProperty('appNativeLibraries').orNull
            if (nativeDirectory != null) {
                android.sourceSets.getByName('main').jniLibs.srcDir(new java.io.File(repositoryRoot, nativeDirectory))
            }
        }
        // Add shared AndroidX dependencies to every application.
        project.dependencies.add('implementation', 'androidx.activity:activity-ktx:1.8.0')
        project.dependencies.add('implementation', 'androidx.lifecycle:lifecycle-runtime-ktx:2.6.1')
        // Check dynamic versions on every build without caching resolution.
        project.configurations.configureEach {
            resolutionStrategy.cacheDynamicVersionsFor(0, 'seconds')
        }
    }
}