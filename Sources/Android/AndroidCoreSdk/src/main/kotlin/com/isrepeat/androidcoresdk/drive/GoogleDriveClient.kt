package com.isrepeat.androidcoresdk.drive

data class GoogleDriveFile(
    val id: String,
    val name: String,
    val mimeType: String? = null,
)

//
// Транспорт Google Drive v3. Авторизацию и прикладной выбор файлов выполняет вызывающее приложение.
//
class GoogleDriveClient(private val accessToken: String) {
    fun ensureFolderPath(path: List<String>): String {
        var parentId = "root"
        path.forEach { name ->
            parentId = findFolder(name, parentId) ?: createFolder(name, parentId)
        }
        return parentId
    }

    fun listFiles(parentId: String, pageSize: Int = 100): List<GoogleDriveFile> {
        val query = "'$parentId' in parents and trashed = false"
        val fields = encode("files(id,name,mimeType)")
        val response = read(
            java.net.URL("$FILES_URL?q=${encode(query)}&pageSize=$pageSize&fields=$fields"),
        )
        val files = org.json.JSONObject(response).getJSONArray("files")
        return (0 until files.length()).map { index ->
            files.getJSONObject(index).let { file ->
                GoogleDriveFile(
                    id = file.getString("id"),
                    name = file.getString("name"),
                    mimeType = file.optString("mimeType"),
                )
            }
        }
    }

    fun download(id: String, destination: java.io.File) {
        download(id, destination) { _, _ -> }
    }

    fun download(id: String, destination: java.io.File, progress: (Long, Long) -> Unit) {
        val response = connection(java.net.URL("$FILES_URL/$id?alt=media"), "GET")
        response.useInput { input ->
            val total = response.contentLengthLong
            var downloaded = 0L
            progress(downloaded, total)
            destination.outputStream().use { output ->
                val buffer = ByteArray(64 * 1024)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    output.write(buffer, 0, count)
                    downloaded += count
                    progress(downloaded, total)
                }
            }
        }
    }

    fun upload(
        parentId: String,
        name: String,
        mimeType: String,
        openInputStream: () -> java.io.InputStream?,
    ) {
        val boundary = "AndroidCoreSdk${System.currentTimeMillis()}"
        val connection = connection(java.net.URL(UPLOAD_URL), "POST").apply {
            doOutput = true
            setChunkedStreamingMode(0)
            setRequestProperty("Content-Type", "multipart/related; boundary=$boundary")
        }
        connection.outputStream.buffered().use { output ->
            output.write("--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".toByteArray())
            output.write(
                org.json.JSONObject().apply {
                    put("name", name)
                    put("mimeType", mimeType)
                    put("parents", listOf(parentId))
                }.toString().toByteArray(),
            )
            output.write("\r\n--$boundary\r\nContent-Type: $mimeType\r\n\r\n".toByteArray())
            openInputStream()?.use { input ->
                input.copyTo(output)
            } ?: error("Failed to open the source file.")
            output.write("\r\n--$boundary--\r\n".toByteArray())
        }
        requireSuccess(connection)
        connection.disconnect()
    }

    private fun findFolder(name: String, parentId: String): String? {
        val safeName = name.replace("'", "\\'")
        val query = "name = '$safeName' and mimeType = '$FOLDER_MIME_TYPE' " +
            "and '$parentId' in parents and trashed = false"
        val response = read(
            java.net.URL("$FILES_URL?q=${encode(query)}&pageSize=1&fields=${encode("files(id)")}"),
        )
        return org.json.JSONObject(response).getJSONArray("files").optJSONObject(0)?.optString("id")
    }

    private fun createFolder(name: String, parentId: String): String {
        val connection = connection(java.net.URL(FILES_URL), "POST").apply {
            doOutput = true
            setRequestProperty("Content-Type", "application/json; charset=UTF-8")
        }
        connection.outputStream.bufferedWriter().use { writer ->
            writer.write(
                org.json.JSONObject().apply {
                    put("name", name)
                    put("mimeType", FOLDER_MIME_TYPE)
                    put("parents", listOf(parentId))
                }.toString(),
            )
        }
        requireSuccess(connection)
        return org.json.JSONObject(connection.inputStream.bufferedReader().use { reader -> reader.readText() })
            .getString("id")
            .also { connection.disconnect() }
    }

    private fun read(url: java.net.URL): String {
        val connection = connection(url, "GET")
        return connection.inputStream.bufferedReader().use { reader -> reader.readText() }
            .also { connection.disconnect() }
    }

    private fun connection(url: java.net.URL, method: String): java.net.HttpURLConnection =
        (url.openConnection() as java.net.HttpURLConnection).apply {
            requestMethod = method
            connectTimeout = 15_000
            readTimeout = 120_000
            setRequestProperty("Authorization", "Bearer $accessToken")
            if (method == "GET") {
                connect()
                requireSuccess(this)
            }
        }

    private fun requireSuccess(connection: java.net.HttpURLConnection) {
        check(connection.responseCode in 200..299) {
            "Google Drive returned HTTP ${connection.responseCode}: " +
                connection.errorStream?.bufferedReader()?.use { reader -> reader.readText() }
        }
    }

    private fun java.net.HttpURLConnection.useInput(action: (java.io.InputStream) -> Unit) {
        try {
            action(inputStream)
        } finally {
            disconnect()
        }
    }

    private fun encode(value: String): String =
        java.net.URLEncoder.encode(value, kotlin.text.Charsets.UTF_8.name())

    private companion object {
        const val FILES_URL = "https://www.googleapis.com/drive/v3/files"
        const val FOLDER_MIME_TYPE = "application/vnd.google-apps.folder"
        const val UPLOAD_URL = "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart"
    }
}