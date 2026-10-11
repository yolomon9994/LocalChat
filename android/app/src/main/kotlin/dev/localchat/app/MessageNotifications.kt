package dev.localchat.app

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.MethodChannel

/** Only opaque peer IDs are retained for tap routing and privacy redaction. */
class MessageNotifications(private val activity: MainActivity, private val bridge: MethodChannel) {
    private val manager = activity.getSystemService(NotificationManager::class.java)
    private val prefs = activity.getSharedPreferences("message_notifications", 0)
    private val previewPeers = mutableSetOf<String>()
    private var accessible = false
    private var foreground = false
    private var pendingPeer: String? = null
    private var permissionResult: MethodChannel.Result? = null

    companion object {
        const val PERMISSION_REQUEST = 1907
        private const val CHANNEL = "messages"
        private const val ACTION = "dev.localchat.OPEN_CHAT"
        private val PEER = Regex("^[a-f0-9]{64}$")
    }

    init {
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(CHANNEL, "Messages", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "Messages received from nearby phones"
                lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            })
        }
        // Remove previews left by a previous process before reading any settings.
        if (!prefs.getBoolean("enabled", false)) manager.cancelAll()
        else for (notification in manager.activeNotifications) {
            val peer = notification.tag
            if (peer != null && PEER.matches(peer)) post(peer, null, null, silent = true)
        }
        acceptIntent(activity.intent, signal = false)
        bridge.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "settings" -> result.success(mapOf(
                        "enabled" to prefs.getBoolean("enabled", false),
                        "previews" to prefs.getBoolean("previews", false),
                        "allowed" to allowed()))
                    "configure" -> {
                        val enabled = call.argument<Boolean>("enabled") == true
                        val previews = call.argument<Boolean>("previews") == true
                        check(prefs.edit().putBoolean("enabled", enabled).putBoolean("previews", previews).commit())
                        if (!enabled) manager.cancelAll()
                        else if (!previews) redact()
                        result.success(null)
                    }
                    "privacy" -> {
                        accessible = call.argument<Boolean>("accessible") == true
                        if (!accessible) redact()
                        result.success(null)
                    }
                    "requestPermission" -> {
                        if (Build.VERSION.SDK_INT >= 33 && activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                            check(permissionResult == null) { "Permission request already open" }
                            permissionResult = result
                            activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), PERMISSION_REQUEST)
                        } else result.success(allowed())
                    }
                    "show" -> {
                        val peer = call.argument<String>("peer") ?: error("Missing peer")
                        require(PEER.matches(peer))
                        if (prefs.getBoolean("enabled", false) && allowed()) {
                            val preview = accessible && foreground && prefs.getBoolean("previews", false)
                            post(peer, if (preview) call.argument<String>("name")?.take(32) else null,
                                if (preview) call.argument<String>("text")?.take(256) else null)
                        }
                        result.success(null)
                    }
                    "cancel" -> {
                        val peer = call.argument<String>("peer")
                        if (peer == null) { manager.cancelAll(); previewPeers.clear(); pendingPeer = null }
                        else { manager.cancel(peer, 1); previewPeers.remove(peer) }
                        result.success(null)
                    }
                    "takeTap" -> {
                        val peer = pendingPeer
                        pendingPeer = null
                        result.success(peer)
                    }
                    "openSettings" -> {
                        val intent = if (Build.VERSION.SDK_INT >= 26) Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).apply {
                            putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
                            putExtra(Settings.EXTRA_CHANNEL_ID, CHANNEL)
                        } else Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${activity.packageName}"))
                        try { activity.startActivity(intent) } catch (_: Exception) {
                            activity.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${activity.packageName}")))
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                result.error("NOTIFICATIONS", "Could not update notifications. Try again in Settings.", null)
            }
        }
    }

    private fun allowed(): Boolean = manager.areNotificationsEnabled() &&
        (Build.VERSION.SDK_INT < 33 || activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) &&
        (Build.VERSION.SDK_INT < 26 || manager.getNotificationChannel(CHANNEL)?.importance != NotificationManager.IMPORTANCE_NONE)

    @Suppress("DEPRECATION")
    private fun builder(): Notification.Builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(activity, CHANNEL) else Notification.Builder(activity)

    private fun post(peer: String, name: String?, text: String?, silent: Boolean = false) {
        if (!allowed()) return
        val intent = Intent(activity, MainActivity::class.java).apply {
            action = ACTION
            data = Uri.parse("localchat://chat/$peer")
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val tap = PendingIntent.getActivity(activity, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val publicVersion = builder().setSmallIcon(R.drawable.ic_stat_message)
            .setContentTitle("LocalChat").setContentText("New message. Unlock LocalChat to read.").build()
        val notification = builder().setSmallIcon(R.drawable.ic_stat_message)
            .setContentTitle(name ?: "LocalChat").setContentText(text ?: "New message. Unlock LocalChat to read.")
            .setContentIntent(tap).setAutoCancel(true).setCategory(Notification.CATEGORY_MESSAGE)
            .setVisibility(Notification.VISIBILITY_PRIVATE).setPublicVersion(publicVersion)
            .setOnlyAlertOnce(silent).setShowWhen(true)
        if (Build.VERSION.SDK_INT < 26 && !silent) notification.setDefaults(Notification.DEFAULT_ALL)
        if (Build.VERSION.SDK_INT >= 29) notification.setAllowSystemGeneratedContextualActions(false)
        manager.notify(peer, 1, notification.build())
        if (name != null || text != null) previewPeers.add(peer) else previewPeers.remove(peer)
    }

    private fun redact() {
        for (peer in previewPeers.toList()) {
            // Never resurrect a notification already dismissed by the user.
            if (manager.activeNotifications.any { it.tag == peer && it.id == 1 }) post(peer, null, null, silent = true)
        }
        previewPeers.clear()
    }

    fun foreground(value: Boolean) {
        foreground = value
        if (!value) { accessible = false; redact() }
    }

    fun acceptIntent(intent: Intent?, signal: Boolean = true) {
        if (intent?.action != ACTION) return
        val uri = intent.data ?: return
        val peer = uri.lastPathSegment ?: return
        if (uri.scheme != "localchat" || uri.host != "chat" || !PEER.matches(peer)) return
        pendingPeer = peer
        intent.action = null
        intent.data = null
        if (signal) bridge.invokeMethod("tapAvailable", null)
    }

    fun permissionFinished() {
        permissionResult?.success(allowed())
        permissionResult = null
    }

    fun dispose() {
        foreground(false)
        permissionResult?.error("CANCELLED", "Activity closed", null)
        permissionResult = null
        bridge.setMethodCallHandler(null)
    }
}
