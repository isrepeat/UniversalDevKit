package com.isrepeat.androidcoresdk.diagnostics

//
// Единая точка записи диагностических сообщений AndroidCoreSdk.
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