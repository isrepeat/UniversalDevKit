package com.isrepeat.androidappkit

// Общая точка входа: приложение передаёт только свои идентификаторы и native-мост.
data class AppIdentity(
    val name: String,
    val storageDirectory: String,
)

fun interface NativeLogConfigurator {
    fun configure(nativePath: String)
}