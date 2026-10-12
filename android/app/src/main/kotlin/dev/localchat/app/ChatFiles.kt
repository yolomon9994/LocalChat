package dev.localchat.app

import android.app.Activity
import android.content.Intent
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/** User-selected documents only. Never resolve a received name as a path. */
class ChatFiles(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "dev.localchat/files")
    private val io = Executors.newSingleThreadExecutor()
    private var pending: MethodChannel.Result? = null
    private var savingBytes: ByteArray? = null
    private var disposed = false
    companion object { private const val PICK = 1908; private const val SAVE = 1909; private const val MAX = 8 * 1024 * 1024 }
    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "pick" && call.method != "save") result.notImplemented()
            else if (pending != null) result.error("FILE_BUSY", "A file picker is already open.", null)
            else try {
                val saving = call.method == "save"
                val bytes = if (saving) call.argument<ByteArray>("bytes") else null
                if (saving) require(bytes != null && bytes.size in 1..MAX)
                val name = call.argument<String>("name") ?: "attachment.bin"
                if (saving) require(name.isNotBlank() && !name.contains('/') && !name.contains('\\'))
                savingBytes = bytes
                pending = result
                activity.startActivityForResult(Intent(if (saving) Intent.ACTION_CREATE_DOCUMENT else Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = if (saving) "application/octet-stream" else "*/*"
                    putExtra(Intent.EXTRA_LOCAL_ONLY, true)
                    if (saving) putExtra(Intent.EXTRA_TITLE, name)
                }, if (saving) SAVE else PICK)
            } catch (_: Exception) {
                pending = null; savingBytes = null
                result.error("FILE_PICKER", "Could not open the system file picker.", null)
            }
        }
    }
    fun onActivityResult(request: Int, code: Int, data: Intent?): Boolean {
        if (request != PICK && request != SAVE) return false
        val result = pending ?: return true
        val uri = data?.data
        val export = savingBytes
        if (code != Activity.RESULT_OK || uri == null) {
            pending = null; savingBytes = null
            result.success(if (request == SAVE) false else null)
            return true
        }
        io.execute {
            try {
                val value: Any = if (request == SAVE) {
                    require(export != null)
                    activity.contentResolver.openOutputStream(uri, "wt")!!.use { it.write(export) }
                    true
                } else {
                    var name = "attachment.bin"
                    activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { cursor ->
                        if (cursor.moveToFirst()) {
                            val nameColumn = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                            if (nameColumn >= 0 && !cursor.isNull(nameColumn)) name = cursor.getString(nameColumn)
                            val sizeColumn = cursor.getColumnIndex(OpenableColumns.SIZE)
                            if (sizeColumn >= 0 && !cursor.isNull(sizeColumn)) require(cursor.getLong(sizeColumn) <= MAX)
                        }
                    }
                    val bytes = activity.contentResolver.openInputStream(uri)!!.use { stream ->
                        val output = ByteArrayOutputStream()
                        val buffer = ByteArray(8192)
                        while (true) {
                            val count = stream.read(buffer)
                            if (count < 0) break
                            require(output.size() + count <= MAX)
                            output.write(buffer, 0, count)
                        }
                        require(output.size() > 0)
                        output.toByteArray()
                    }
                    mapOf("name" to name, "bytes" to bytes)
                }
                activity.runOnUiThread {
                    if (!disposed && pending === result) { pending = null; savingBytes = null; result.success(value) }
                }
            } catch (_: Exception) {
                activity.runOnUiThread {
                    if (!disposed && pending === result) {
                        pending = null; savingBytes = null
                        result.error("FILE_IO", "Could not read or save this file (nonempty, maximum 8 MiB).", null)
                    }
                }
            }
        }
        return true
    }
    fun dispose() {
        disposed = true
        channel.setMethodCallHandler(null)
        pending?.error("FILE_CLOSED", "File selection was interrupted.", null)
        pending = null; savingBytes = null
        io.shutdownNow()
    }
}
