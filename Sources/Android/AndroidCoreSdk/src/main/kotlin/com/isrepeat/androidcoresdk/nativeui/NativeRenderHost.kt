package com.isrepeat.androidcoresdk.nativeui

//
// Kotlin adapter contract for the application's JNI renderer.
//
interface NativeRenderHost {
    fun log(message: String)
    fun onSurfaceChanged(surface: android.view.Surface, width: Int, height: Int)
    fun onSurfaceDestroyed()
    fun onTouch(action: Int, x: Float, y: Float)
    fun render()
}