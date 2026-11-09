package com.isrepeat.build

import org.gradle.api.DefaultTask
import org.gradle.api.GradleException
import org.gradle.api.provider.Property
import org.gradle.api.tasks.Input
import org.gradle.api.tasks.TaskAction

abstract class VerifyReleaseSigning extends DefaultTask {
    @Input
    abstract Property<Boolean> getConfigured()

    @TaskAction
    void verify() {
        if (!configured.get()) {
            throw new GradleException('Release requires androidSigningProperties, ANDROID_SIGNING_PROPERTIES or an explicit signingConfig with an existing keystore.')
        }
    }
}