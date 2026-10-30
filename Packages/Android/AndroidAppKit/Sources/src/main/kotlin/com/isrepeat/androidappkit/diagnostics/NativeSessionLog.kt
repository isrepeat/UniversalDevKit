package com.isrepeat.androidappkit.diagnostics

import com.isrepeat.androidappkit.androidappkit
import com.isrepeat.androidcoresdk.androidcoresdk

//
// Создаёт один журнал сеанса и передаёт file descriptor нативной части приложения.
//
class NativeSessionLog(
    private val identity: androidappkit.AppIdentity,
    private val configureNativeLog: androidappkit.NativeLogConfigurator,
) {
    private var uri: android.net.Uri? = null

    @Synchronized
    fun configure(context: android.content.Context): android.net.Uri {
        uri?.let { currentUri -> return currentUri }
        val sessionLog = androidcoresdk.diagnostics.MediaStoreSessionLog.create(
            context,
            identity.storageDirectory,
            identity.name,
        )
        configureNativeLog.configure(sessionLog.nativePath)
        return sessionLog.uri.also { createdUri -> uri = createdUri }
    }

    @Synchronized
    fun currentUri(): android.net.Uri? = uri
}