package {{PackageId}}

// Forward Kotlin diagnostics to the current host's native logger.
object NativeDiagnostics {
    fun log(message: String) {
        nativeLog(message)
    }

    private external fun nativeLog(message: String)
}