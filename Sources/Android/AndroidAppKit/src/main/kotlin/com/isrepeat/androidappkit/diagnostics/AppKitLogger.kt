package com.isrepeat.androidappkit.diagnostics

//
// Forward AndroidAppKit messages to the application's logger.
//
fun interface AppKitLogger {
    fun log(message: String)
}

object AppKitDiagnostics {
    @Volatile
    private var logger: AppKitLogger? = null

    fun configure(logger: AppKitLogger) {
        this.logger = logger
    }

    fun log(message: String) {
        logger?.log(message)
    }
}