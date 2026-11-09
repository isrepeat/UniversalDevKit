package com.isrepeat.androidcoresdk.nativeui

data class NativeMessage(val signal: Int, val value: String, val additionalValue: String)

class NativeMessageDispatcher {
    @Volatile
    var handler: ((NativeMessage) -> Unit)? = null

    fun dispatch(signal: Int, value: String, additionalValue: String) {
        handler?.invoke(NativeMessage(signal, value, additionalValue))
    }
}