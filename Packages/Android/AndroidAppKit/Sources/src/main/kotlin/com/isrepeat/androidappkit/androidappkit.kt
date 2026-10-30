package com.isrepeat.androidappkit

//
// Псевдопространства имён и типизированные фасады для публичного API AppKit.
//
object androidappkit {
    // Короткая публичная точка входа для Activity с native OpenGL-сессией.
    abstract class NativeOpenGlActivity : com.isrepeat.androidappkit.NativeOpenGlActivity()

    data class AppIdentity(val name: String, val storageDirectory: String)

    fun interface NativeLogConfigurator {
        fun configure(nativePath: String)
    }

    object drive {
        data class GoogleDriveUploadConfiguration(val folderPath: List<String>)

        sealed interface GoogleDriveUploadResult {
            data class Success(val fileName: String) : GoogleDriveUploadResult
            data class Failure(val message: String) : GoogleDriveUploadResult
        }

        class GoogleDriveUploader(
            activity: androidx.activity.ComponentActivity,
            configuration: GoogleDriveUploadConfiguration,
            requestAuthorization: (androidx.activity.result.IntentSenderRequest) -> Unit,
            complete: (GoogleDriveUploadResult) -> Unit,
            logger: diagnostics.AppKitLogger = diagnostics.sharedLogger(),
        ) {
            private val uploader = com.isrepeat.androidappkit.drive.GoogleDriveUploader(
                activity = activity,
                configuration = com.isrepeat.androidappkit.drive.GoogleDriveUploadConfiguration(configuration.folderPath),
                requestAuthorization = requestAuthorization,
                complete = { result ->
                    complete(
                        when (result) {
                            is com.isrepeat.androidappkit.drive.GoogleDriveUploadResult.Success -> GoogleDriveUploadResult.Success(result.fileName)
                            is com.isrepeat.androidappkit.drive.GoogleDriveUploadResult.Failure -> GoogleDriveUploadResult.Failure(result.message)
                        },
                    )
                },
                logger = logger,
            )

            fun upload(file: java.io.File, mimeType: String = "application/octet-stream") = uploader.upload(file, mimeType)
            fun upload(uri: android.net.Uri, mimeType: String? = null, fileName: String? = null) = uploader.upload(uri, mimeType, fileName)
            fun completeAuthorization(intent: android.content.Intent?) = uploader.completeAuthorization(intent)
        }
    }

    object diagnostics {
        fun interface AppKitLogger {
            fun log(message: String)
        }

        private val sharedLogger = AppKitLogger { message ->
            com.isrepeat.androidappkit.diagnostics.AppKitDiagnostics.log(message)
        }

        fun configureLogger(logger: AppKitLogger) {
            com.isrepeat.androidappkit.diagnostics.AppKitDiagnostics.configure(
                com.isrepeat.androidappkit.diagnostics.AppKitLogger { message -> logger.log(message) },
            )
            com.isrepeat.androidcoresdk.androidcoresdk.diagnostics.configureLogger(
                com.isrepeat.androidcoresdk.androidcoresdk.diagnostics.SdkLogger { message -> logger.log(message) },
            )
        }

        fun sharedLogger(): AppKitLogger = sharedLogger

        class NativeSessionLog(identity: AppIdentity, configureNativeLog: NativeLogConfigurator) {
            private val log = com.isrepeat.androidappkit.diagnostics.NativeSessionLog(
                identity,
            ) { nativePath -> configureNativeLog.configure(nativePath) }

            fun configure(context: android.content.Context) = log.configure(context)
            fun currentUri() = log.currentUri()
        }
    }
    object media {
        fun SurfaceScreenshotCapture(directoryName: String, filePrefix: String) =
            com.isrepeat.androidappkit.media.SurfaceScreenshotCapture(directoryName, filePrefix)
    }

    object update {
        data class GoogleDriveUpdateConfiguration(
            val driveFolderPath: List<String>,
            val apkNamePattern: Regex,
            val versionCodeFromName: (MatchResult) -> Long,
            val updaterPackage: String = com.isrepeat.androidappkit.update.ApkUpdaterProtocol.packageName,
            val updaterActivity: String = com.isrepeat.androidappkit.update.ApkUpdaterProtocol.activityName,
            val updaterPermission: String = com.isrepeat.androidappkit.update.ApkUpdaterProtocol.installPermission,
            val updaterAction: String = com.isrepeat.androidappkit.update.ApkUpdaterProtocol.installAction,
            val confirmSameVersionInUpdater: Boolean = false,
        )

        class GoogleDriveUpdateController(
            activity: androidx.activity.ComponentActivity,
            configuration: GoogleDriveUpdateConfiguration,
            requestAuthorization: (androidx.activity.result.IntentSenderRequest) -> Unit,
            status: (String) -> Unit,
            logger: diagnostics.AppKitLogger = diagnostics.sharedLogger(),
            confirmSameVersion: (onConfirmed: () -> Unit, onCancelled: () -> Unit) -> Unit =
                { onConfirmed, _ -> onConfirmed() },
        ) {
            private val controller = com.isrepeat.androidappkit.update.GoogleDriveUpdateController(
                activity,
                com.isrepeat.androidappkit.update.GoogleDriveUpdateConfiguration(
                    configuration.driveFolderPath,
                    configuration.apkNamePattern,
                    configuration.versionCodeFromName,
                    configuration.updaterPackage,
                    configuration.updaterActivity,
                    configuration.updaterPermission,
                    configuration.updaterAction,
                    confirmSameVersionInUpdater = configuration.confirmSameVersionInUpdater,
                ),
                requestAuthorization,
                status,
                logger,
                confirmSameVersion,
            )

            fun start() = controller.start()
            fun completeAuthorization(intent: android.content.Intent?) = controller.completeAuthorization(intent)
        }

        data class ApkUpdaterResult(
            val trace: String?,
            val error: String?,
            val installed: Boolean,
        )

        fun readApkUpdaterResult(intent: android.content.Intent): ApkUpdaterResult =
            ApkUpdaterResult(
                intent.getStringExtra(com.isrepeat.androidappkit.update.ApkUpdaterProtocol.traceExtra),
                intent.getStringExtra(com.isrepeat.androidappkit.update.ApkUpdaterProtocol.errorExtra),
                intent.action == com.isrepeat.androidappkit.update.ApkUpdaterProtocol.updateCompletedAction,
            )
    }
}