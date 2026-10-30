package com.isrepeat.androidappkit.drive

import com.isrepeat.androidappkit.androidappkit

data class GoogleDriveUploadConfiguration(val folderPath: List<String>)

sealed interface GoogleDriveUploadResult {
    data class Success(val fileName: String) : GoogleDriveUploadResult
    data class Failure(val message: String) : GoogleDriveUploadResult
}

class GoogleDriveUploader(
    private val activity: androidx.activity.ComponentActivity,
    private val configuration: GoogleDriveUploadConfiguration,
    private val requestAuthorization: (androidx.activity.result.IntentSenderRequest) -> Unit,
    private val complete: (GoogleDriveUploadResult) -> Unit,
    private val logger: androidappkit.diagnostics.AppKitLogger = androidappkit.diagnostics.sharedLogger(),
) {
    private data class PendingFile(val name: String, val mimeType: String, val open: () -> java.io.InputStream?)

    private var pendingFile: PendingFile? = null
    private var isRunning = false

    fun upload(file: java.io.File, mimeType: String = "application/octet-stream") {
        if (!file.isFile) {
            logger.log("Upload rejected because ${file.name} is not a file.")
            complete(GoogleDriveUploadResult.Failure("File ${file.name} was not found."))
            return
        }
        logger.log("Upload requested for ${file.name}, ${file.length()} bytes.")
        upload(PendingFile(file.name, mimeType, file::inputStream))
    }

    fun upload(uri: android.net.Uri, mimeType: String? = null, fileName: String? = null) {
        val name = fileName ?: uri.lastPathSegment?.substringAfterLast('/') ?: "upload"
        val type = mimeType ?: activity.contentResolver.getType(uri) ?: "application/octet-stream"
        logger.log("Upload requested for content URI as $name.")
        upload(PendingFile(name, type) { activity.contentResolver.openInputStream(uri) })
    }

    fun completeAuthorization(intent: android.content.Intent?) {
        logger.log("Received Google Drive upload authorization result. intentPresent=${intent != null}")
        runCatching {
            com.google.android.gms.auth.api.identity.Identity
                .getAuthorizationClient(activity)
                .getAuthorizationResultFromIntent(intent)
        }
            .onSuccess(::handleAuthorization)
            .onFailure { error ->
                logger.log("Google Drive upload authorization result could not be read: ${error::class.simpleName}: ${error.message}")
                finish(GoogleDriveUploadResult.Failure("Google Drive access was not granted: ${error.message}"))
            }
    }

    private fun upload(file: PendingFile) {
        if (isRunning) {
            logger.log("Upload request ignored because another upload is already running.")
            complete(GoogleDriveUploadResult.Failure("A Google Drive upload is already in progress."))
            return
        }
        isRunning = true
        pendingFile = file
        logger.log("Requesting Google Drive authorization to upload ${file.name}.")
        val request = com.google.android.gms.auth.api.identity.AuthorizationRequest.builder()
            .setRequestedScopes(listOf(com.google.android.gms.common.api.Scope(DRIVE_SCOPE)))
            .build()
        com.google.android.gms.auth.api.identity.Identity.getAuthorizationClient(activity).authorize(request)
            .addOnSuccessListener(::handleAuthorization)
            .addOnFailureListener { error ->
                logger.log("Google Drive upload authorization request failed: ${error::class.simpleName}: ${error.message}")
                finish(GoogleDriveUploadResult.Failure("Google Drive access was not granted: ${error.message}"))
            }
    }

    private fun handleAuthorization(result: com.google.android.gms.auth.api.identity.AuthorizationResult) {
        logger.log("Google Drive upload authorization completed. requiresResolution=${result.hasResolution()}, accessTokenPresent=${result.accessToken != null}")
        if (result.hasResolution()) {
            val pendingIntent = result.pendingIntent
            if (pendingIntent == null) {
                logger.log("Google Drive upload authorization requires resolution, but PendingIntent is absent.")
                finish(GoogleDriveUploadResult.Failure("Google did not provide an authorization screen."))
                return
            }
            logger.log("Launching Google Drive upload authorization screen.")
            requestAuthorization(
                androidx.activity.result.IntentSenderRequest.Builder(pendingIntent.intentSender).build(),
            )
            return
        }
        val token = result.accessToken
        if (token == null) {
            logger.log("Google Drive upload authorization completed without an access token.")
            finish(GoogleDriveUploadResult.Failure("Google did not provide a Drive access token."))
            return
        }
        val file = pendingFile
        if (file == null) {
            logger.log("Google Drive upload authorization completed without a selected file.")
            finish(GoogleDriveUploadResult.Failure("No file was selected for upload."))
            return
        }
        logger.log("Google Drive access token received. Uploading ${file.name} to ${configuration.folderPath.joinToString("/")}.")
        com.isrepeat.androidcoresdk.androidcoresdk.coroutines.LifecycleCoroutineRunner.launch(activity) {
            val result = runCatching {
                kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                    com.isrepeat.androidcoresdk.androidcoresdk.drive.GoogleDriveClient(token).run {
                        upload(ensureFolderPath(configuration.folderPath), file.name, file.mimeType, file.open)
                    }
                }
            }.fold(
                onSuccess = {
                    logger.log("Google Drive upload completed for ${file.name}.")
                    GoogleDriveUploadResult.Success(file.name)
                },
                onFailure = { error ->
                    logger.log("Google Drive upload failed for ${file.name}: ${error::class.simpleName}: ${error.message}")
                    GoogleDriveUploadResult.Failure("Failed to upload ${file.name}: ${error.message}")
                },
            )
            finish(result)
        }
    }

    private fun finish(result: GoogleDriveUploadResult) {
        logger.log("Google Drive upload finished: ${result::class.simpleName}")
        pendingFile = null
        isRunning = false
        complete(result)
    }

    private companion object {
        const val DRIVE_SCOPE = "https://www.googleapis.com/auth/drive"
    }
}