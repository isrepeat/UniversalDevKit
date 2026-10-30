package {{PackageId}}

import com.isrepeat.androidappkit.androidappkit

class MainPage : androidappkit.NativeOpenGlActivity() {
    private val dispatcher = NativeCommandDispatcher { command, _, _ ->
        when (command) {
            HostCommand.REQUEST_APPLICATION_UPDATE -> updateController.start()
            HostCommand.SEND_LOGS -> sendLogs()
        }
    }

    private lateinit var sessionLog: androidappkit.diagnostics.NativeSessionLog
    private lateinit var updateController: androidappkit.update.GoogleDriveUpdateController
    private lateinit var logsUploader: androidappkit.drive.GoogleDriveUploader
    private var reinstallConfirmation: android.app.AlertDialog? = null

    private val authorizeUpdate = registerForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.StartIntentSenderForResult(),
    ) { result -> updateController.completeAuthorization(result.data) }

    private val authorizeLogs = registerForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.StartIntentSenderForResult(),
    ) { result -> logsUploader.completeAuthorization(result.data) }

    //
    // androidappkit.NativeOpenGlActivity
    //
    override fun createNativeSession(): Long {
        return nativeCreate(dispatcher)
    }

    protected external override fun nativeDestroy(handle: Long)
    protected external override fun nativeSurface(handle: Long, width: Int, height: Int)
    protected external override fun nativeReleaseSurface(handle: Long)
    protected external override fun nativeRender(handle: Long)
    protected external override fun nativePointer(handle: Long, action: Int, x: Float, y: Float)
    protected external override fun nativeBack(handle: Long): Boolean

    override fun onPageCreated(savedInstanceState: android.os.Bundle?) {
        sessionLog = androidappkit.diagnostics.NativeSessionLog(
            androidappkit.AppIdentity("{{Application}}", "com.isrepeat/{{Application}}"),
            androidappkit.NativeLogConfigurator { nativePath -> configureNativeLog(nativePath) },
        )
        sessionLog.configure(this)
        androidappkit.diagnostics.configureLogger(
            androidappkit.diagnostics.AppKitLogger { message -> NativeDiagnostics.log(message) },
        )
        val driveFolder = listOf("Android", "{{Application}}")
        logsUploader = androidappkit.drive.GoogleDriveUploader(
            this,
            androidappkit.drive.GoogleDriveUploadConfiguration(driveFolder),
            authorizeLogs::launch,
            { result ->
                if (!isDestroyed) {
                    setStatus(when (result) {
                        is androidappkit.drive.GoogleDriveUploadResult.Success -> "Logs sent: ${result.fileName}"
                        is androidappkit.drive.GoogleDriveUploadResult.Failure -> result.message
                    })
                }
            },
        )
        updateController = androidappkit.update.GoogleDriveUpdateController(
            this,
            androidappkit.update.GoogleDriveUpdateConfiguration(
                driveFolder,
                Regex("{{Application}}-(\\d+)\\.(\\d+)\\.(\\d+)(?:-debug|-release)\\.apk", RegexOption.IGNORE_CASE),
                { match ->
                    match.groupValues[1].toLong() * 1_000_000L +
                        match.groupValues[2].toLong() * 1_000L +
                        match.groupValues[3].toLong()
                },
                confirmSameVersionInUpdater = true,
            ),
            authorizeUpdate::launch,
            { message ->
                if (!isDestroyed) {
                    setStatus(message)
                }
            },
            androidappkit.diagnostics.sharedLogger(),
            { onConfirmed, onCancelled ->
                // Для старого ApkUpdater подтверждение остаётся в приложении.
                reinstallConfirmation = android.app.AlertDialog.Builder(this)
                    .setTitle("Reinstall application?")
                    .setMessage("This version is already installed.")
                    .setPositiveButton("Reinstall") { _, _ -> onConfirmed() }
                    .setNegativeButton("Cancel") { _, _ -> onCancelled() }
                    .setOnCancelListener { _ -> onCancelled() }
                    .show()
            },
        )
    }

    override fun onPageIntent(intent: android.content.Intent) {
        // Диагностика updater попадает в тот же журнал, который отправляет Send logs.
        val result = androidappkit.update.readApkUpdaterResult(intent)
        result.trace?.takeIf { trace -> trace.isNotBlank() }?.let(NativeDiagnostics::log)
        result.error?.let(this::setStatus)
        if (result.installed) {
            setStatus("Update installed.")
        }
    }

    override fun onPageDestroyed() {
        dispatcher.close()
        reinstallConfirmation?.dismiss()
    }

    //
    // Internal
    //
    private external fun nativeCreate(dispatcher: NativeCommandDispatcher): Long
    private external fun nativeConfigureLogFile(handle: Long, path: String)
    private external fun nativeSetStatus(handle: Long, value: ByteArray)

    private fun sendLogs() {
        val uri = sessionLog.currentUri()
        if (uri == null) {
            setStatus("The session log is not available.")
            return
        }
        setStatus("Sending logs to Google Drive…")
        logsUploader.upload(uri, "text/plain", "{{Application}}-session-${System.currentTimeMillis()}.log")
    }

    private fun setStatus(value: String) {
        val bytes = value.toByteArray(Charsets.UTF_8)
        withNativeSession { session -> nativeSetStatus(session, bytes) }
    }

    private fun configureNativeLog(path: String) {
        withNativeSession { session -> nativeConfigureLogFile(session, path) }
    }

    companion object {
        init {
            System.loadLibrary("{{application}}")
        }
    }
}