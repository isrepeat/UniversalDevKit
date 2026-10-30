package {{PackageId}}

// Передаёт диагностические сообщения Kotlin в общий native logger текущего host.
object NativeDiagnostics {
    fun log(message: String) {
        nativeLog(message)
    }

    private external fun nativeLog(message: String)
}