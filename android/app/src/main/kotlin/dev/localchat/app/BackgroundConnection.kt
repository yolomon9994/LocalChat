package dev.localchat.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.Manifest
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference

/** Protects the current in-process session; never creates or restores crypto sessions. */
class BackgroundConnection(
    private val activity: MainActivity,
    private val bridge: MethodChannel,
    private val eligible: (Int, List<String>) -> Boolean,
    private val stopConnection: (Int, String) -> Unit,
    private val changed: (Map<String, Any>) -> Unit
) {
    private val prefs = activity.getSharedPreferences("background_connection", 0)
    private val manager = activity.getSystemService(NotificationManager::class.java)
    private val power = activity.getSystemService(PowerManager::class.java)
    private val main = Handler(Looper.getMainLooper())
    private var pending: MethodChannel.Result? = null
    private var timeout: Runnable? = null
    @Volatile private var generation = -1
    @Volatile private var groupGeneration = 0
    @Volatile private var groupLinks: List<String> = emptyList()
    private fun isEligible(token: Int) = eligible(token,
        if (token == groupGeneration) groupLinks else emptyList())
    var foreground = false
    private var disposed = false

    init {
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(
            NotificationChannel(ConnectionService.CHANNEL, "Connection", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Ongoing nearby connection and connection loss"
                setShowBadge(false)
            })
        if (prefs.getBoolean("active_marker", false)) {
            prefs.edit().putBoolean("active_marker", false).putString("reason", "closed").apply()
        }
        ConnectionService.owner = WeakReference(this)
        bridge.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "status" -> result.success(status())
                    "configure" -> {
                        val enabled = call.argument<Boolean>("enabled") == true
                        check(prefs.edit().putBoolean("enabled", enabled).commit())
                        if (enabled) prefs.edit().remove("reason").apply()
                        if (!enabled) deactivate()
                        result.success(null)
                    }
                    "start" -> {
                        val token = call.argument<Int>("generation") ?: error("No live connection")
                        check(foreground && isEligible(token)) { "Return to the verified chat first" }
                        check(prefs.getBoolean("enabled", false))
                        if (!allowed()) {
                            result.error("NOTIFICATIONS_BLOCKED", "Allow connection notifications.", null)
                        } else if (ConnectionService.activeEpoch != 0 &&
                            ConnectionService.activeEpoch == ConnectionService.desiredEpoch && generation == token) {
                            result.success(status())
                        } else {
                            check(pending == null)
                            generation = token
                            val epoch = ++ConnectionService.nextEpoch
                            ConnectionService.desiredEpoch = epoch
                            pending = result
                            timeout = Runnable {
                                if (ConnectionService.desiredEpoch == epoch && pending != null) {
                                    deactivate()
                                    emitFailure()
                                }
                            }.also { main.postDelayed(it, 5000) }
                            val intent = Intent(activity, ConnectionService::class.java).apply {
                                action = ConnectionService.START
                                putExtra("epoch", epoch)
                                putExtra("generation", token)
                            }
                            if (Build.VERSION.SDK_INT >= 26) activity.startForegroundService(intent)
                            else activity.startService(intent)
                        }
                    }
                    "stop" -> { deactivate(clearLoss = false); result.success(null) }
                    "groupLinks" -> {
                        val token = call.argument<Int>("generation") ?: error("Missing group generation")
                        val ids = call.argument<List<String>>("links") ?: error("Missing verified links")
                        require(token < 0 && ids.size <= 7 && ids.distinct().size == ids.size)
                        if (eligible(token, ids)) {
                            groupGeneration = token
                            groupLinks = ids.toList()
                        }
                        result.success(null)
                    }
                    "frameProcessed" -> {
                        call.argument<Int>("generation")?.let { ConnectionService.finishFrame(it) }
                        result.success(null)
                    }
                    "openSettings" -> {
                        val target = call.argument<String>("target")
                        val intent = when (target) {
                            "battery" -> Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                            "notifications" -> if (Build.VERSION.SDK_INT >= 26) Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).apply {
                                putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
                                putExtra(Settings.EXTRA_CHANNEL_ID, ConnectionService.CHANNEL)
                            } else Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${activity.packageName}"))
                            else -> error("Unknown settings target")
                        }
                        try { activity.startActivity(intent) } catch (_: Exception) {
                            activity.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${activity.packageName}")))
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                if (pending === result) deactivate()
                else result.error("BACKGROUND", "Could not protect the connection. Return to the app and try again.", null)
            }
        }
    }

    fun status(): Map<String, Any> = mapOf(
        "enabled" to prefs.getBoolean("enabled", false),
        "active" to (ConnectionService.activeEpoch != 0 && ConnectionService.activeEpoch == ConnectionService.desiredEpoch),
        "allowed" to allowed(),
        "batteryExempt" to power.isIgnoringBatteryOptimizations(activity.packageName),
        "generation" to generation,
        "reason" to (prefs.getString("reason", "") ?: ""))

    private fun allowed() = manager.areNotificationsEnabled() &&
        (Build.VERSION.SDK_INT < 33 || activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) &&
        (Build.VERSION.SDK_INT < 26 || manager.getNotificationChannel(ConnectionService.CHANNEL)?.importance != NotificationManager.IMPORTANCE_NONE)

    fun mayRun(epoch: Int, token: Int) = !disposed && epoch == ConnectionService.desiredEpoch &&
        token == generation && prefs.getBoolean("enabled", false) && isEligible(token) && allowed()

    fun holdGroupFrame(token: Int, link: String): Boolean =
        token == generation && token == groupGeneration && groupLinks.contains(link) &&
            ConnectionService.holdFrame(token)

    fun started(epoch: Int) {
        if (epoch != ConnectionService.desiredEpoch || disposed) return
        timeout?.let { main.removeCallbacks(it) }; timeout = null
        prefs.edit().putBoolean("active_marker", true).remove("reason").apply()
        pending?.success(status()); pending = null
        changed(status())
    }

    fun failed(epoch: Int) {
        if (epoch != ConnectionService.desiredEpoch || disposed) return
        deactivate()
        emitFailure()
    }

    private fun emitFailure() {
        prefs.edit().putString("reason", "system").apply()
        changed(status())
    }

    fun stopped(reason: String) {
        if (disposed) return
        if (reason == "user") prefs.edit().putBoolean("enabled", false).apply()
        prefs.edit().putString("reason", reason).apply()
        deactivate()
        changed(status())
        stopConnection(generation, reason)
    }

    fun connectionClosed(reason: String, token: Int) {
        if (token != generation) return
        if (token < 0 && reason == "member" && isEligible(token)) return
        val finalReason = if (reason == "member") "lost" else reason
        val wasActive = ConnectionService.desiredEpoch != 0
        if (wasActive) prefs.edit().putString("reason", finalReason).apply()
        deactivate(clearLoss = false)
        if (wasActive) {
            if (finalReason == "lost" && allowed()) ConnectionService.showLoss(activity)
            changed(status())
        }
    }

    private fun deactivate(clearLoss: Boolean = true) {
        ConnectionService.desiredEpoch = 0
        ConnectionService.releaseFrames()
        timeout?.let { main.removeCallbacks(it) }; timeout = null
        pending?.error("BACKGROUND_CANCELLED", "Background connection start cancelled.", null)
        pending = null
        prefs.edit().putBoolean("active_marker", false).apply()
        activity.stopService(Intent(activity, ConnectionService::class.java))
        manager.cancel(ConnectionService.NOTIFICATION)
        if (clearLoss) manager.cancel(ConnectionService.LOSS_NOTIFICATION)
    }

    fun dispose() {
        if (ConnectionService.desiredEpoch != 0) prefs.edit().putString("reason", "closed").apply()
        deactivate()
        disposed = true
        if (ConnectionService.owner?.get() === this) ConnectionService.owner = null
        bridge.setMethodCallHandler(null)
    }
}
