package {{PackageId}}

// Числа совпадают с HostCommand в C++; ordinal не является частью контракта.
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

    // Вызывается на UI-потоке до освобождения native-сессии.
    fun close() {
        handler = null
        ui.removeCallbacksAndMessages(null)
    }
}