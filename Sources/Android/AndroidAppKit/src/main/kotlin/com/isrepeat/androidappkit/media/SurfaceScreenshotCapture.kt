package com.isrepeat.androidappkit.media

//
// Configurable PixelCopy wrapper for an OpenGL SurfaceView.
//
class SurfaceScreenshotCapture(
    private val directoryName: String,
    private val filePrefix: String,
) {
    suspend fun capture(surface: android.view.SurfaceView, cacheDir: java.io.File): java.io.File =
        com.isrepeat.androidcoresdk.androidcoresdk.media.ScreenshotCapture.capture(
            surface,
            cacheDir,
            directoryName,
            filePrefix,
        )
}