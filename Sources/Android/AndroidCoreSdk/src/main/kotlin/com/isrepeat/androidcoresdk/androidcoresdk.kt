package com.isrepeat.androidcoresdk

//
// Псевдопространства имён для краткого обращения к публичным объектам SDK.
//
object androidcoresdk {
    object coroutines {
        val CancellableContinuationCompletion =
            com.isrepeat.androidcoresdk.coroutines.CancellableContinuationCompletion
        val LifecycleCoroutineRunner =
            com.isrepeat.androidcoresdk.coroutines.LifecycleCoroutineRunner
    }
    object drive {
        fun GoogleDriveClient(accessToken: String) =
            com.isrepeat.androidcoresdk.drive.GoogleDriveClient(accessToken)
    }
    object diagnostics {
        val MediaStoreSessionLog = com.isrepeat.androidcoresdk.diagnostics.MediaStoreSessionLog

        fun interface SdkLogger {
            fun log(message: String)
        }

        private val sharedLogger = SdkLogger { message ->
            com.isrepeat.androidcoresdk.diagnostics.SdkDiagnostics.log(message)
        }

        fun configureLogger(logger: SdkLogger) {
            com.isrepeat.androidcoresdk.diagnostics.SdkDiagnostics.configure(
                com.isrepeat.androidcoresdk.diagnostics.SdkLogger { message -> logger.log(message) },
            )
        }

        fun sharedLogger(): SdkLogger = sharedLogger
    }
    object media {
        val ScreenshotCapture = com.isrepeat.androidcoresdk.media.ScreenshotCapture
    }
    object nativeui {
        fun NativeMessage(
            signal: Int,
            value: String,
            additionalValue: String,
        ) = com.isrepeat.androidcoresdk.nativeui.NativeMessage(signal, value, additionalValue)
        fun NativeMessageDispatcher() = com.isrepeat.androidcoresdk.nativeui.NativeMessageDispatcher()
        fun NativeRenderSurfaceView(
            context: android.content.Context,
            host: com.isrepeat.androidcoresdk.nativeui.NativeRenderHost,
        ) = com.isrepeat.androidcoresdk.nativeui.NativeRenderSurfaceView(context, host)
    }
}