package dev.localchat.app

import android.app.Activity
import android.content.Intent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/** Read only a user-selected document; no gallery-wide/storage permission. */
class ImageFiles(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "dev.localchat/images")
    private val io = Executors.newSingleThreadExecutor()
    private var pending: MethodChannel.Result? = null
    private var disposed = false
    companion object { private const val PICK = 1907; private const val MAX = 8 * 1024 * 1024 }
    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "pick") result.notImplemented()
            else if (pending != null) result.error("IMAGE_BUSY", "An image picker is already open.", null)
            else try {
                pending = result
                activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "image/*"
                    putExtra(Intent.EXTRA_LOCAL_ONLY, true)
                }, PICK)
            } catch (_: Exception) {
                pending = null
                result.error("IMAGE_PICKER", "Could not open the image picker.", null)
            }
        }
    }
    fun onActivityResult(request: Int, code: Int, data: Intent?): Boolean {
        if (request != PICK) return false
        val result = pending ?: return true
        val uri = data?.data
        if (code != Activity.RESULT_OK || uri == null) {
            pending = null; result.success(null); return true
        }
        io.execute {
            try {
                val bytes = activity.contentResolver.openInputStream(uri)!!.use { stream ->
                    val output = ByteArrayOutputStream()
                    val buffer = ByteArray(8192)
                    while (true) {
                        val count = stream.read(buffer)
                        if (count < 0) break
                        require(output.size() + count <= MAX)
                        output.write(buffer, 0, count)
                    }
                    output.toByteArray()
                }
                activity.runOnUiThread {
                    if (!disposed && pending === result) { pending = null; result.success(bytes) }
                }
            } catch (_: Exception) {
                activity.runOnUiThread {
                    if (!disposed && pending === result) {
                        pending = null; result.error("IMAGE_IO", "Could not read this image (maximum 8 MiB).", null)
                    }
                }
            }
        }
        return true
    }
    fun dispose() {
        disposed = true
        channel.setMethodCallHandler(null)
        pending?.error("IMAGE_CLOSED", "Image selection was interrupted.", null)
        pending = null
        io.shutdownNow()
    }
}
