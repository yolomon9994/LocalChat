package dev.localchat.app

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.os.Handler
import android.os.Looper
import android.net.Uri
import java.lang.ref.WeakReference

/** A user-visible lease for the live Activity/Flutter session, with no restart. */
class ConnectionService : Service() {
    @Volatile private var epoch = 0
    @Volatile private var generation = -1
    private var wake: PowerManager.WakeLock? = null
    private var frames = 0
    private var expectedStop = false
    private val main = Handler(Looper.getMainLooper())
    private val checkConnection = object : Runnable {
        override fun run() {
            if (activeEpoch != epoch || desiredEpoch != epoch || epoch == 0) return
            if (owner?.get()?.mayRun(epoch, generation) != true) {
                expectedStop = true
                owner?.get()?.stopped("system")
                stopSelf()
            } else main.postDelayed(this, 15000)
        }
    }

    companion object {
        const val CHANNEL = "background_connection"
        const val NOTIFICATION = 3201
        const val LOSS_NOTIFICATION = 3202
        const val START = "dev.localchat.BACKGROUND_START"
        const val STOP = "dev.localchat.BACKGROUND_STOP"
        var owner: WeakReference<BackgroundConnection>? = null
        var nextEpoch = 0
        @Volatile var desiredEpoch = 0
        @Volatile var activeEpoch = 0
        @Volatile private var instance: WeakReference<ConnectionService>? = null

        @Suppress("DEPRECATION")
        private fun builder(context: Context): Notification.Builder =
            if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, CHANNEL) else Notification.Builder(context)

        private fun openApp(context: Context) = PendingIntent.getActivity(context, 3201,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

        fun showLoss(context: Context) {
            context.getSystemService(NotificationManager::class.java).notify(LOSS_NOTIFICATION,
                builder(context).setSmallIcon(R.drawable.ic_stat_message).setContentTitle("LocalChat connection ended")
                    .setContentText("Open Nearby or Group chats to reconnect and verify again.")
                    .setContentIntent(openApp(context)).setAutoCancel(true).setOnlyAlertOnce(true)
                    .setVisibility(Notification.VISIBILITY_PUBLIC).build())
        }

        fun holdFrame(token: Int): Boolean = instance?.get()?.hold(token) ?: false
        fun finishFrame(token: Int) { instance?.get()?.finish(token) }
        fun releaseFrames() { instance?.get()?.release() }
    }

    override fun onCreate() {
        super.onCreate()
        instance = WeakReference(this)
        wake = getSystemService(PowerManager::class.java).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "LocalChat:received-frame").apply {
            setReferenceCounted(false)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == STOP) {
            val token = intent.getIntExtra("epoch", 0)
            if (token != desiredEpoch || token != activeEpoch) {
                if (desiredEpoch == 0) { expectedStop = true; stopSelf() }
                return START_NOT_STICKY
            }
            expectedStop = true
            owner?.get()?.stopped("user")
            stopSelf()
            return START_NOT_STICKY
        }
        if (intent?.action != START) { expectedStop = true; stopSelf(); return START_NOT_STICKY }
        epoch = intent.getIntExtra("epoch", 0)
        generation = intent.getIntExtra("generation", -1)
        expectedStop = false
        try {
            val stop = PendingIntent.getService(this, 3201, Intent(this, ConnectionService::class.java).apply {
                action = STOP
                data = Uri.parse("localchat://background-stop/$epoch")
                putExtra("epoch", epoch)
            }, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val notification = builder(this).setSmallIcon(R.drawable.ic_stat_message)
                .setContentTitle("LocalChat connection active")
                .setContentText("Receiving on the current verified nearby connection.")
                .setContentIntent(openApp(this)).setOngoing(true).setOnlyAlertOnce(true)
                .setCategory(Notification.CATEGORY_SERVICE).setVisibility(Notification.VISIBILITY_PUBLIC)
                .addAction(Notification.Action.Builder(null, "Stop", stop).build()).build()
            // Promote every accepted start request promptly, even if cancelled in transit.
            if (Build.VERSION.SDK_INT >= 34) startForeground(NOTIFICATION, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING)
            else startForeground(NOTIFICATION, notification)
            if (owner?.get()?.mayRun(epoch, generation) != true) {
                expectedStop = true
                owner?.get()?.failed(epoch)
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            } else {
                activeEpoch = epoch
                getSystemService(NotificationManager::class.java).cancel(LOSS_NOTIFICATION)
                owner?.get()?.started(epoch)
                main.removeCallbacks(checkConnection)
                main.postDelayed(checkConnection, 15000)
            }
        } catch (_: Exception) {
            expectedStop = true
            owner?.get()?.failed(epoch)
            stopSelf()
        }
        return START_NOT_STICKY
    }

    @Synchronized private fun hold(token: Int): Boolean {
        if (token != generation || activeEpoch != epoch || desiredEpoch != epoch || epoch == 0) return false
        frames++
        // Wake only for actual decrypt/persist/ACK work, never throughout idle chat.
        wake?.acquire(15000)
        return true
    }
    @Synchronized private fun finish(token: Int) {
        if (token != generation || frames == 0) return
        frames--
        if (frames == 0 && wake?.isHeld == true) wake?.release()
    }
    @Synchronized private fun release() {
        frames = 0
        if (wake?.isHeld == true) wake?.release()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        if (desiredEpoch != 0 && epoch != desiredEpoch) return
        expectedStop = true
        if (epoch != 0 && epoch == desiredEpoch) owner?.get()?.stopped("closed")
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }
    override fun onDestroy() {
        main.removeCallbacks(checkConnection)
        release()
        if (activeEpoch == epoch) activeEpoch = 0
        if (instance?.get() === this) instance = null
        if (!expectedStop && epoch != 0 && desiredEpoch == epoch) owner?.get()?.stopped("system")
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }
    override fun onBind(intent: Intent?): IBinder? = null
}
