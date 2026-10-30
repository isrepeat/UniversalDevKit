package com.isrepeat.androidappkit.update

import com.isrepeat.androidappkit.androidappkit

//
// Ищет APK на Google Drive, проверяет его и передаёт доверенному updater-приложению.
//
class GoogleDriveUpdateController(
    private val activity: androidx.activity.ComponentActivity,
    private val configuration: GoogleDriveUpdateConfiguration,
    private val requestAuthorization: (androidx.activity.result.IntentSenderRequest) -> Unit,
    private val status: (String) -> Unit,
    private val logger: androidappkit.diagnostics.AppKitLogger = androidappkit.diagnostics.sharedLogger(),
    private val confirmSameVersion: (onConfirmed: () -> Unit, onCancelled: () -> Unit) -> Unit =
        { onConfirmed, _ -> onConfirmed() },
) {
    private var isRunning = false

    fun start() {
        if (isRunning) {
            logger.log("Update request ignored because another update is already running.")
            status("An update is already in progress.")
            return
        }
        isRunning = true
        logger.log("Requesting Google Drive authorization for update discovery.")
        status("Checking Google Drive access…")
        val request = com.google.android.gms.auth.api.identity.AuthorizationRequest.builder()
            .setRequestedScopes(listOf(com.google.android.gms.common.api.Scope(DRIVE_SCOPE)))
            .build()
        com.google.android.gms.auth.api.identity.Identity.getAuthorizationClient(activity).authorize(request)
            .addOnSuccessListener(::handleAuthorization)
            .addOnFailureListener { error ->
                logger.log("Google Drive authorization request failed: ${error::class.simpleName}: ${error.message}")
                finish("Google Drive access was not granted: ${error.message}")
            }
    }

    fun completeAuthorization(intent: android.content.Intent?) {
        logger.log("Received Google Drive authorization activity result. intentPresent=${intent != null}")
        runCatching {
            com.google.android.gms.auth.api.identity.Identity.getAuthorizationClient(activity)
                .getAuthorizationResultFromIntent(intent)
        }.onSuccess(::handleAuthorization)
            .onFailure { error ->
                logger.log("Google Drive authorization result could not be read: ${error::class.simpleName}: ${error.message}")
                finish("Google Drive access was not granted: ${error.message}")
            }
    }

    private fun handleAuthorization(result: com.google.android.gms.auth.api.identity.AuthorizationResult) {
        logger.log("Google Drive authorization completed. requiresResolution=${result.hasResolution()}, accessTokenPresent=${result.accessToken != null}")
        if (result.hasResolution()) {
            val pendingIntent = result.pendingIntent
            if (pendingIntent == null) {
                logger.log("Google Drive authorization requires resolution, but PendingIntent is absent.")
                finish("Google did not provide an authorization screen.")
                return
            }
            logger.log("Launching Google Drive authorization screen.")
            requestAuthorization(androidx.activity.result.IntentSenderRequest.Builder(pendingIntent.intentSender).build())
            return
        }
        val token = result.accessToken
        if (token == null) {
            logger.log("Google Drive authorization completed without an access token.")
            finish("Google did not provide a Drive access token.")
            return
        }
        logger.log("Google Drive access token received. Looking for update APK.")
        com.isrepeat.androidcoresdk.androidcoresdk.coroutines.LifecycleCoroutineRunner.launch(activity) {
            runCatching { kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) { download(token) } }
                .onSuccess { apk ->
                    if (apk == null) {
                        logger.log("No APK matching the configured version pattern was found.")
                        finish("No new version was found on Google Drive.")
                    } else {
                        confirmOrLaunch(apk)
                    }
                }
                .onFailure { error ->
                    logger.log("Google Drive update download failed: ${error::class.simpleName}: ${error.message}")
                    finish("Failed to update the application: ${error.message}")
                }
        }
    }

    private fun download(token: String): java.io.File? {
        reportDownloadStatus("Looking for update APK on Google Drive…")
        logger.log("Opening Google Drive folder: ${configuration.driveFolderPath.joinToString("/")}")
        val client = com.isrepeat.androidcoresdk.androidcoresdk.drive.GoogleDriveClient(token)
        val candidate = client.listFiles(client.ensureFolderPath(configuration.driveFolderPath))
            .mapNotNull { file -> configuration.apkNamePattern.matchEntire(file.name)?.let { match -> file to configuration.versionCodeFromName(match) } }
            .maxByOrNull { candidate -> candidate.second } ?: return null
        logger.log("Selected update APK ${candidate.first.name}, versionCode=${candidate.second}.")
        val apk = java.io.File(activity.cacheDir, "self-updates/update.apk").apply { parentFile?.mkdirs() }
        try {
            reportDownloadStatus("Downloading ${candidate.first.name}…")
            // Ограничиваем частоту уведомлений, чтобы не перегружать главный поток.
            var lastProgressTime = 0L
            client.download(candidate.first.id, apk) { downloaded, total ->
                val now = android.os.SystemClock.elapsedRealtime()
                if (now - lastProgressTime >= 250L || (total > 0L && downloaded >= total)) {
                    lastProgressTime = now
                    val megabytes = "%.1f".format(java.util.Locale.ROOT, downloaded / 1048576.0)
                    val message = if (total > 0L) {
                        "Downloading update: ${downloaded * 100 / total}% ($megabytes MB)…"
                    } else {
                        "Downloading update: $megabytes MB…"
                    }
                    reportDownloadStatus(message)
                }
            }
            reportDownloadStatus("Download complete. Validating APK…")
            logger.log("Downloaded ${apk.length()} bytes. Validating APK.")
            validateApk(apk)
            return apk
        } catch (exception: Exception) {
            apk.delete()
            throw exception
        }
    }

    private fun validateApk(apk: java.io.File) {
        val archive = activity.packageManager.getPackageArchiveInfo(apk.path, 0)
            ?: error("Google Drive returned an invalid APK.")
        check(archive.packageName == activity.packageName) { "The APK targets ${archive.packageName}, not ${activity.packageName}." }
        val downloadedVersion = versionCode(archive)
        val installedVersion = installedVersionCode()
        check(downloadedVersion >= installedVersion) { "Google Drive contains only an older version." }
        logger.log("APK validation succeeded. downloadedVersion=$downloadedVersion, installedVersion=$installedVersion.")
    }

    private fun confirmOrLaunch(apk: java.io.File) {
        val version = activity.packageManager.getPackageArchiveInfo(apk.path, 0)?.let(::versionCode)
        if (version == null) {
            logger.log("Downloaded APK version could not be read.")
            finish("Failed to read the downloaded APK version.")
            return
        }
        if (version != installedVersionCode()) {
            logger.log("Downloaded APK has a newer version. Starting updater.")
            launchUpdaterAndFinish(apk)
            return
        }
        logger.log("Downloaded APK matches the installed version. Requesting reinstall confirmation.")
        if (configuration.confirmSameVersionInUpdater && supportsPreparedReinstallConfirmation()) {
            // Updater сначала готовит сессию, затем показывает подтверждение.
            launchUpdaterAndFinish(apk, confirmSameVersion = true)
            return
        }
        confirmSameVersion({ launchUpdaterAndFinish(apk) }, { finish("Reinstallation was cancelled.") })
    }

    @Suppress("DEPRECATION")
    private fun supportsPreparedReinstallConfirmation(): Boolean = runCatching {
        val component = android.content.ComponentName(configuration.updaterPackage, configuration.updaterActivity)
        val info = activity.packageManager.getActivityInfo(component, android.content.pm.PackageManager.GET_META_DATA)
        val supported = info.metaData?.getBoolean("com.isrepeat.apkupdater.PREPARED_REINSTALL_CONFIRMATION", false) == true
        logger.log("Updater supports prepared reinstall confirmation: $supported")
        supported
    }.getOrElse { error ->
        logger.log("Could not read updater capabilities: ${error.message}. Using application confirmation.")
        false
    }

    private fun launchUpdaterAndFinish(apk: java.io.File, confirmSameVersion: Boolean = false) {
        status("Starting updater…")
        runCatching {
            logger.log("Checking updater signature and permission.")
            val pm = activity.packageManager
            check(pm.checkSignatures(activity.packageName, configuration.updaterPackage) == android.content.pm.PackageManager.SIGNATURE_MATCH) { "The application and updater are signed with different keys." }
            check(pm.checkPermission(configuration.updaterPermission, activity.packageName) == android.content.pm.PackageManager.PERMISSION_GRANTED) { "Android did not grant permission to invoke the updater application." }
            val uri = androidx.core.content.FileProvider.getUriForFile(activity, "${activity.packageName}.fileprovider", apk)
            activity.startActivity(android.content.Intent(configuration.updaterAction)
                .setClassName(configuration.updaterPackage, configuration.updaterActivity)
                .setDataAndType(uri, APK_MIME_TYPE)
                .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK or
                    android.content.Intent.FLAG_ACTIVITY_NO_ANIMATION or
                    android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION)
                .putExtra(configuration.targetPackageExtra, activity.packageName)
                .putExtra("confirm_same_version", confirmSameVersion),
                android.app.ActivityOptions.makeCustomAnimation(activity, 0, 0).toBundle())
            logger.log("Update passed to the updater application: ${apk.length()} bytes")
        }.onSuccess { finish("Update passed to the updater application. Waiting for installation…") }
            .onFailure { error ->
                logger.log("Updater launch failed: ${error::class.simpleName}: ${error.message}")
                finish("Failed to start the updater application: ${error.message}")
            }
    }

    private fun finish(message: String) {
        logger.log("Update finished: $message")
        isRunning = false
        status(message)
    }

    private fun reportDownloadStatus(message: String) {
        // UI и JNI-обработчики статуса вызываются только в главном потоке.
        activity.runOnUiThread { status(message) }
    }

    @Suppress("DEPRECATION")
    private fun versionCode(info: android.content.pm.PackageInfo): Long =
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) info.longVersionCode else info.versionCode.toLong()

    @Suppress("DEPRECATION")
    private fun installedVersionCode(): Long = versionCode(activity.packageManager.getPackageInfo(activity.packageName, 0))

    private companion object {
        const val APK_MIME_TYPE = "application/vnd.android.package-archive"
        const val DRIVE_SCOPE = "https://www.googleapis.com/auth/drive"
    }
}