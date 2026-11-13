package {{PackageId}}

// Values match the C++ HostCommand enum and do not depend on ordinals.
enum class HostCommand(val id: Int) {
    REQUEST_APPLICATION_UPDATE(1),
    SEND_LOGS(2);

    companion object {
        fun fromId(id: Int): HostCommand? {
            return entries.firstOrNull { command -> command.id == id }
        }
    }
}

class NativeCommandDispatcher(handler: (HostCommand, String, String) -> Unit) {
    private val ui = android.os.Handler(android.os.Looper.getMainLooper())
    private var handler: ((HostCommand, String, String) -> Unit)? = handler

    @androidx.annotation.Keep
    fun dispatch(id: Int, value: ByteArray, additionalValue: ByteArray) {
        val command = HostCommand.fromId(id) ?: return
        val text = value.toString(Charsets.UTF_8)
        val additionalText = additionalValue.toString(Charsets.UTF_8)
        ui.post { handler?.invoke(command, text, additionalText) }
    }

    // Call on the UI thread before releasing the native session.
    fun close() {
        handler = null
        ui.removeCallbacksAndMessages(null)
    }
}