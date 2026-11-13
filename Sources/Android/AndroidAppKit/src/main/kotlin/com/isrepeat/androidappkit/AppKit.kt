package com.isrepeat.androidappkit

// Shared entry point. The application supplies its IDs and native bridge.
data class AppIdentity(
    val name: String,
    val storageDirectory: String,
)

fun interface NativeLogConfigurator {
    fun configure(nativePath: String)
}