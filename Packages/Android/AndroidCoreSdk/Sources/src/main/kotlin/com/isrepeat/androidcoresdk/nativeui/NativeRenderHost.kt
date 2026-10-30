package com.isrepeat.androidcoresdk.nativeui

//
// Контракт Kotlin-адаптера над JNI-рендерером приложения.
//
interface NativeRenderHost {
    fun log(message: String)
    fun onSurfaceChanged(surface: android.view.Surface, width: Int, height: Int)
    fun onSurfaceDestroyed()
    fun onTouch(action: Int, x: Float, y: Float)
    fun render()
}