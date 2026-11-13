package com.isrepeat.androidcoresdk.diagnostics

//
// Common entry point for AndroidCoreSdk diagnostics.
//
fun interface SdkLogger {
    fun log(message: String)
}

object SdkDiagnostics {
    @Volatile
    private var logger: SdkLogger? = null

    fun configure(logger: SdkLogger) {
        this.logger = logger
    }

    fun log(message: String) {
        logger?.log(message)
    }
}