package com.isrepeat.androidcoresdk.media

import com.isrepeat.androidcoresdk.androidcoresdk

object ScreenshotCapture {
    suspend fun capture(
        surface: android.view.SurfaceView,
        cacheDir: java.io.File,
        directoryName: String,
        filePrefix: String,
    ): java.io.File {
        val bitmap = captureBitmap(surface)
        val directory = java.io.File(cacheDir, directoryName).apply { mkdirs() }
        val name = "$filePrefix-${java.text.SimpleDateFormat("yyyy-MM-dd_HH-mm-ss", java.util.Locale.US).format(java.util.Date())}.png"
        return java.io.File(directory, name).also { file ->
            try {
                java.io.FileOutputStream(file).use { output ->
                    check(bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, output)) {
                        "Failed to save PNG."
                    }
                }
            } finally {
                bitmap.recycle()
            }
        }
    }

    private suspend fun captureBitmap(surface: android.view.SurfaceView): android.graphics.Bitmap =
        kotlinx.coroutines.suspendCancellableCoroutine { continuation ->
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.O) {
            androidcoresdk.coroutines.CancellableContinuationCompletion.fail(
                continuation,
                UnsupportedOperationException("PixelCopy requires Android 8.0 or later."),
            )
            return@suspendCancellableCoroutine
        }
        if (!surface.holder.surface.isValid || surface.width <= 0 || surface.height <= 0) {
            androidcoresdk.coroutines.CancellableContinuationCompletion.fail(
                continuation,
                IllegalStateException("OpenGL surface is unavailable."),
            )
            return@suspendCancellableCoroutine
        }
        val bitmap = android.graphics.Bitmap.createBitmap(
            surface.width,
            surface.height,
            android.graphics.Bitmap.Config.ARGB_8888,
        )
        android.view.PixelCopy.request(
            surface.holder.surface,
            bitmap,
            { result ->
                if (result == android.view.PixelCopy.SUCCESS) {
                    androidcoresdk.coroutines.CancellableContinuationCompletion.succeed(
                        continuation,
                        bitmap,
                    )
                } else {
                    bitmap.recycle()
                    androidcoresdk.coroutines.CancellableContinuationCompletion.fail(
                        continuation,
                        IllegalStateException("PixelCopy failed: $result"),
                    )
                }
            },
            android.os.Handler(android.os.Looper.getMainLooper()),
        )
    }
}