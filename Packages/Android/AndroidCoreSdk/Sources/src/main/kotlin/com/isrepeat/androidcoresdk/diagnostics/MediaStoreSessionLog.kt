package com.isrepeat.androidcoresdk.diagnostics

data class SessionLog(val uri: android.net.Uri, val nativePath: String)

//
// Создаёт доступный пользователю файл журнала и возвращает путь для native-кода.
//
object MediaStoreSessionLog {
    fun create(
        context: android.content.Context,
        directory: String,
        filePrefix: String,
    ): SessionLog {
        check(android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
            "Public session logs via MediaStore require Android 10 or later."
        }
        val timestamp = java.text.SimpleDateFormat(
            "yyyy-MM-dd-HH-mm-ss",
            java.util.Locale.US,
        ).format(java.util.Date())
        val values = android.content.ContentValues().apply {
            put(android.provider.MediaStore.Downloads.DISPLAY_NAME, "$filePrefix-session-$timestamp.log")
            put(android.provider.MediaStore.Downloads.MIME_TYPE, "text/plain")
            put(
                android.provider.MediaStore.Downloads.RELATIVE_PATH,
                "${android.os.Environment.DIRECTORY_DOWNLOADS}/$directory",
            )
        }
        val uri = checkNotNull(
            context.contentResolver.insert(
                android.provider.MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                values,
            ),
        ) {
            "Failed to create the session log in Downloads."
        }
        val descriptor = checkNotNull(context.contentResolver.openFileDescriptor(uri, "rw")) {
            "Failed to open the session log."
        }
        return SessionLog(uri, "/proc/self/fd/${descriptor.detachFd()}")
    }
}