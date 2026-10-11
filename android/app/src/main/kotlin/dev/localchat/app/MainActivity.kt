package dev.localchat.app

import android.Manifest
import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.wifi.p2p.WifiP2pConfig
import android.net.wifi.p2p.WifiP2pManager
import android.net.wifi.p2p.nsd.WifiP2pDnsSdServiceInfo
import android.net.wifi.p2p.nsd.WifiP2pDnsSdServiceRequest
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterFragmentActivity
import android.view.WindowManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.nio.charset.StandardCharsets
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/** Android transport only. All message cryptography and verification live in Dart. */
class MainActivity : FlutterFragmentActivity(), EventChannel.StreamHandler {
    private var sink: EventChannel.EventSink? = null
    private var manager: WifiP2pManager? = null
    private var channel: WifiP2pManager.Channel? = null
    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newCachedThreadPool()
    private val watchdog = Executors.newSingleThreadScheduledExecutor()
    private val generation = AtomicInteger(0)
    private val lock = Any()
    @Volatile private var socket: Socket? = null
    @Volatile private var server: ServerSocket? = null
    @Volatile private var output: DataOutputStream? = null
    private var socketStarting = false
    private var registered = false
    private var active = false
    private var service: WifiP2pDnsSdServiceInfo? = null
    private var request: WifiP2pDnsSdServiceRequest? = null
    private var permissionResult: MethodChannel.Result? = null
    private var pendingName = "LocalChat user"
    private var backupResult: MethodChannel.Result? = null
    private var backupBytes: ByteArray? = null
    private val peers = linkedMapOf<String, Map<String, String>>()
    private var scanEpoch = 0
    private var scanEnd: Runnable? = null

    companion object {
        private const val PORT = 45873
        private const val MAX_FRAME = 65536
        private const val PERMISSION_REQUEST = 1904
        private const val BACKUP_PICK = 1905
        private const val BACKUP_SAVE = 1906
        private const val MAX_BACKUP = 20 * 1024 * 1024 + 65
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Protect the initial window until Flutter has read persisted settings.
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.localchat/backup").setMethodCallHandler { call, result ->
            if (call.method != "pick" && call.method != "save") {
                result.notImplemented()
            } else if (backupResult != null) {
                result.error("BACKUP_BUSY", "A file picker is already open.", null)
            } else {
                try {
                    val saving = call.method == "save"
                    val bytes = if (saving) call.argument<ByteArray>("bytes") else null
                    if (saving) require(bytes != null && bytes.size in 66..MAX_BACKUP)
                    val intent = Intent(if (saving) Intent.ACTION_CREATE_DOCUMENT else Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = if (saving) "application/octet-stream" else "*/*"
                        if (saving) putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: "localchat.lcbackup")
                    }
                    backupBytes = bytes
                    backupResult = result
                    startActivityForResult(intent, if (saving) BACKUP_SAVE else BACKUP_PICK)
                } catch (_: Exception) {
                    backupBytes = null
                    backupResult = null
                    result.error("BACKUP_PICKER", "Could not open the system file picker.", null)
                }
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.localchat/privacy").setMethodCallHandler { call, result ->
            if (call.method == "setSecure") {
                if (call.argument<Boolean>("enabled") == true) {
                    window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                } else {
                    window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                }
                result.success(null)
            } else result.notImplemented()
        }
        manager = getSystemService(Context.WIFI_P2P_SERVICE) as? WifiP2pManager
        channel = manager?.initialize(this, mainLooper) {
            active = false
            closeSockets()
            emit("error", "message" to "Wi-Fi Direct service stopped. Restart LocalChat.")
        }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.localchat/events").setStreamHandler(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.localchat/transport").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "start" -> {
                        val name = call.argument<String>("name")?.trim() ?: "LocalChat user"
                        require(name.isNotEmpty() && name.length <= 32) { "Use a name with 1–32 characters" }
                        start(name, result)
                    }
                    "scan" -> scan(result)
                    "connect" -> {
                        ensureReady()
                        val address = call.argument<String>("address") ?: error("Missing address")
                        require(peers.containsKey(address)) { "Device is no longer in the nearby list. Scan again." }
                        val config = WifiP2pConfig().apply { deviceAddress = address }
                        manager!!.connect(channel!!, config, action(result))
                    }
                    "send" -> {
                        val bytes = (call.argument<String>("frame") ?: error("Missing frame")).toByteArray(StandardCharsets.UTF_8)
                        require(bytes.size in 1..MAX_FRAME) { "Frame exceeds size limit" }
                        val token = generation.get()
                        io.execute {
                            try {
                                synchronized(lock) {
                                    check(token == generation.get()) { "Connection changed" }
                                    val stream = output ?: error("No peer connected")
                                    stream.writeInt(bytes.size)
                                    stream.write(bytes)
                                    stream.flush()
                                }
                                main.post { result.success(null) }
                            } catch (e: Exception) {
                                failConnection(token, "Could not send message. Reconnect to the peer.")
                                main.post { result.error("SEND_FAILED", e.message, null) }
                            }
                        }
                    }
                    "disconnect" -> disconnect(result)
                    "stop" -> { stop(); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) { result.error("LOCALCHAT", e.message, null) }
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) { sink = events }
    @Deprecated("Used for the Flutter platform channel file picker")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != BACKUP_PICK && requestCode != BACKUP_SAVE) return
        val result = backupResult ?: return
        val bytes = backupBytes
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            backupResult = null; backupBytes = null
            result.success(if (requestCode == BACKUP_SAVE) false else null)
            return
        }
        backupBytes = null
        io.execute {
            try {
                val value: Any = if (requestCode == BACKUP_SAVE) {
                    contentResolver.openOutputStream(uri, "w")!!.use { stream ->
                        stream.write(bytes!!); stream.flush()
                    }
                    true
                } else {
                    contentResolver.openInputStream(uri)!!.use { stream ->
                        val output = ByteArrayOutputStream()
                        val buffer = ByteArray(8192)
                        while (true) {
                            val count = stream.read(buffer)
                            if (count < 0) break
                            require(output.size() + count <= MAX_BACKUP)
                            output.write(buffer, 0, count)
                        }
                        output.toByteArray()
                    }
                }
                main.post {
                    if (backupResult === result) { backupResult = null; result.success(value) }
                }
            } catch (_: Exception) {
                main.post {
                    if (backupResult === result) {
                        backupResult = null
                        result.error("BACKUP_IO", "Could not read or save the backup (maximum 20 MB).", null)
                    }
                }
            }
        }
    }
    override fun onCancel(arguments: Any?) { sink = null }
    private fun emit(type: String, vararg fields: Pair<String, Any?>) {
        main.post { sink?.success(mapOf("type" to type, *fields)) }
    }
    private fun action(result: MethodChannel.Result) = object : WifiP2pManager.ActionListener {
        override fun onSuccess() { result.success(null) }
        override fun onFailure(reason: Int) { result.error("WIFI_DIRECT", reasonText(reason), null) }
    }
    private fun reasonText(reason: Int) = when (reason) {
        WifiP2pManager.P2P_UNSUPPORTED -> "This phone does not support Wi-Fi Direct."
        WifiP2pManager.BUSY -> "Wi-Fi Direct is busy. Disconnect, wait a moment, and scan again."
        else -> "Wi-Fi Direct failed ($reason). Turn on Wi-Fi and check permissions."
    }
    private fun permission() = if (Build.VERSION.SDK_INT >= 33) Manifest.permission.NEARBY_WIFI_DEVICES else Manifest.permission.ACCESS_FINE_LOCATION
    private fun ensureReady() {
        check(active && manager != null && channel != null) { "Tap Go nearby first." }
        check(checkSelfPermission(permission()) == PackageManager.PERMISSION_GRANTED) { "Allow nearby device permission in Android Settings." }
        if (Build.VERSION.SDK_INT < 33) {
            val location = getSystemService(Context.LOCATION_SERVICE) as LocationManager
            check(location.isProviderEnabled(LocationManager.GPS_PROVIDER) || location.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                "Turn on Location for Wi-Fi Direct discovery on this Android version."
            }
        }
    }
    private fun start(name: String, result: MethodChannel.Result) {
        check(manager != null && channel != null && packageManager.hasSystemFeature(PackageManager.FEATURE_WIFI_DIRECT)) {
            "This phone does not support Wi-Fi Direct."
        }
        if (checkSelfPermission(permission()) != PackageManager.PERMISSION_GRANTED) {
            check(permissionResult == null) { "A permission request is already open." }
            permissionResult = result
            pendingName = name
            requestPermissions(arrayOf(permission()), PERMISSION_REQUEST)
            return
        }
        advertise(name, result)
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != PERMISSION_REQUEST) return
        val result = permissionResult ?: return
        permissionResult = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            try { advertise(pendingName, result) } catch (e: Exception) { result.error("LOCALCHAT", e.message, null) }
        } else { result.error("PERMISSION_DENIED", "Allow nearby devices (or Location on older Android) to connect offline.", null) }
    }
    private fun advertise(name: String, result: MethodChannel.Result) {
        if (!registered) {
            val filter = IntentFilter().apply {
                addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION)
                addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
                addAction(WifiP2pManager.WIFI_P2P_DISCOVERY_CHANGED_ACTION)
            }
            if (Build.VERSION.SDK_INT >= 33) registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
            else registerReceiver(receiver, filter)
            registered = true
        }
        manager!!.setDnsSdResponseListeners(channel!!,
            { _, _, _ -> },
            { domain, record, device ->
                if (active && domain.contains("_localchat._tcp") && record["app"] == "localchat" && record["v"] == "1") {
                    val remoteName = record["name"]?.take(32) ?: "LocalChat user"
                    peers[device.deviceAddress] = mapOf("address" to device.deviceAddress, "name" to remoteName)
                    emit("peers", "peers" to peers.values.toList())
                }
            })
        val newService = WifiP2pDnsSdServiceInfo.newInstance("localchat", "_localchat._tcp",
            mapOf("app" to "localchat", "v" to "1", "name" to name))
        manager!!.clearLocalServices(channel!!, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                manager!!.addLocalService(channel!!, newService, object : WifiP2pManager.ActionListener {
                    override fun onSuccess() { service = newService; active = true; result.success(null) }
                    override fun onFailure(reason: Int) { result.error("ADVERTISE", reasonText(reason), null) }
                })
            }
            override fun onFailure(reason: Int) { result.error("ADVERTISE", reasonText(reason), null) }
        })
    }
    private fun scan(result: MethodChannel.Result) {
        ensureReady()
        peers.clear()
        emit("peers", "peers" to emptyList<Map<String, String>>())
        val epoch = ++scanEpoch
        scanEnd?.let { main.removeCallbacks(it) }
        emit("scanning", "active" to true)
        manager!!.clearServiceRequests(channel!!, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                if (epoch != scanEpoch || !active) { result.error("CANCELLED", "Scan stopped", null); return }
                val newRequest = WifiP2pDnsSdServiceRequest.newInstance("_localchat._tcp")
                request = newRequest
                manager!!.addServiceRequest(channel!!, newRequest, object : WifiP2pManager.ActionListener {
                    override fun onSuccess() {
                        manager!!.discoverServices(channel!!, object : WifiP2pManager.ActionListener {
                            override fun onSuccess() {
                                result.success(null)
                                scanEnd = Runnable {
                                    if (epoch == scanEpoch) {
                                        manager?.stopPeerDiscovery(channel, null)
                                        emit("scanning", "active" to false)
                                    }
                                }.also { main.postDelayed(it, 15000) }
                            }
                            override fun onFailure(reason: Int) { scanFailed(result, reason) }
                        })
                    }
                    override fun onFailure(reason: Int) { scanFailed(result, reason) }
                })
            }
            override fun onFailure(reason: Int) { scanFailed(result, reason) }
        })
    }
    private fun scanFailed(result: MethodChannel.Result, reason: Int) {
        emit("scanning", "active" to false)
        result.error("DISCOVERY", reasonText(reason), null)
    }
    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            try {
                when (intent.action) {
                    WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION -> {
                        val enabled = intent.getIntExtra(WifiP2pManager.EXTRA_WIFI_STATE, -1) == WifiP2pManager.WIFI_P2P_STATE_ENABLED
                        emit("wifi", "enabled" to enabled)
                        if (!enabled) { closeSockets(); emit("disconnected") }
                    }
                    WifiP2pManager.WIFI_P2P_DISCOVERY_CHANGED_ACTION -> {
                        if (intent.getIntExtra(WifiP2pManager.EXTRA_DISCOVERY_STATE, -1) == WifiP2pManager.WIFI_P2P_DISCOVERY_STOPPED)
                            emit("scanning", "active" to false)
                    }
                    WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION -> if (active) {
                        val queryToken = generation.get()
                        manager?.requestConnectionInfo(channel) { info ->
                            if (!active || queryToken != generation.get()) return@requestConnectionInfo
                            if (info.groupFormed) {
                                if (!socketStarting && socket == null) {
                                    socketStarting = true
                                    val token = generation.get()
                                    val address = info.groupOwnerAddress?.hostAddress
                                    io.execute { openSocket(token, info.isGroupOwner, address) }
                                }
                            } else if (socketStarting || socket != null) {
                                closeSockets()
                                emit("disconnected")
                            }
                        }
                    }
                }
            } catch (e: SecurityException) { emit("error", "message" to "Nearby permission was removed. Restart LocalChat.") }
        }
    }
    private fun openSocket(token: Int, owner: Boolean, address: String?) {
        var candidate: Socket? = null
        try {
            if (owner) {
                val listener = ServerSocket().apply { reuseAddress = true; bind(InetSocketAddress(PORT)); soTimeout = 90000 }
                synchronized(lock) {
                    if (token != generation.get()) { listener.close(); return }
                    server = listener
                }
                candidate = listener.accept()
                listener.close()
                synchronized(lock) { if (server === listener) server = null }
            } else {
                require(address != null) { "Missing Wi-Fi Direct group address" }
                var last: Exception? = null
                for (attempt in 0 until 15) {
                    if (token != generation.get()) return
                    val attemptSocket = Socket()
                    try {
                        attemptSocket.connect(InetSocketAddress(address, PORT), 2000)
                        candidate = attemptSocket
                        break
                    } catch (e: Exception) {
                        attemptSocket.close(); last = e; Thread.sleep(400)
                    }
                }
                if (candidate == null) throw last ?: IllegalStateException("Could not connect")
            }
            val connected = candidate ?: error("Missing socket")
            connected.tcpNoDelay = true
            connected.keepAlive = true
            synchronized(lock) {
                if (token != generation.get()) { connected.close(); return }
                socket = connected
                output = DataOutputStream(BufferedOutputStream(connected.getOutputStream()))
            }
            main.post {
                if (token == generation.get()) { socketStarting = false; sink?.success(mapOf("type" to "connected")) }
            }
            val input = DataInputStream(BufferedInputStream(connected.getInputStream()))
            while (token == generation.get()) {
                connected.soTimeout = 0 // Idle chat is allowed; partially sent frames are bounded.
                val first = input.read()
                if (first < 0) break
                connected.soTimeout = 15000
                val deadline = watchdog.schedule({ connected.runCatching { close() } }, 15, TimeUnit.SECONDS)
                val frame = try {
                    val length = (first shl 24) or (input.readUnsignedByte() shl 16) or
                        (input.readUnsignedByte() shl 8) or input.readUnsignedByte()
                    require(length in 1..MAX_FRAME) { "Invalid frame size" }
                    val bytes = ByteArray(length)
                    input.readFully(bytes)
                    StandardCharsets.UTF_8.newDecoder()
                        .onMalformedInput(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString()
                } finally { deadline.cancel(false) }
                main.post {
                    if (token == generation.get()) sink?.success(mapOf("type" to "frame", "frame" to frame))
                }
            }
            failConnection(token, null)
        } catch (e: Exception) {
            candidate?.runCatching { close() }
            failConnection(token, "Peer connection ended. Reconnect from Nearby devices.")
        }
    }
    private fun failConnection(token: Int, message: String?) {
        main.post {
            if (token == generation.get()) {
                closeSockets()
                manager?.removeGroup(channel, null)
                if (message != null) emit("error", "message" to message)
                emit("disconnected")
            }
        }
    }
    private fun closeSockets() {
        generation.incrementAndGet()
        // Close without the writer lock: a blocked write must be interruptible.
        socket?.runCatching { close() }
        server?.runCatching { close() }
        socket = null; server = null; output = null; socketStarting = false
    }
    private fun disconnect(result: MethodChannel.Result) {
        closeSockets()
        val p2p = manager
        val ch = channel
        if (p2p == null || ch == null) { emit("disconnected"); result.success(null); return }
        p2p.cancelConnect(ch, null)
        p2p.removeGroup(ch, object : WifiP2pManager.ActionListener {
            override fun onSuccess() { emit("disconnected"); result.success(null) }
            override fun onFailure(reason: Int) { emit("disconnected"); result.success(null) }
        })
    }
    private fun stop() {
        active = false
        ++scanEpoch
        scanEnd?.let { main.removeCallbacks(it) }
        closeSockets()
        if (manager != null && channel != null) {
            runCatching {
                manager?.cancelConnect(channel, null)
                manager?.stopPeerDiscovery(channel, null)
                manager?.clearLocalServices(channel, null)
                manager?.clearServiceRequests(channel, null)
                manager?.removeGroup(channel, null)
            }
        }
        service = null; request = null
        if (registered) { unregisterReceiver(receiver); registered = false }
    }
    override fun onDestroy() {
        backupResult?.error("CANCELLED", "Activity closed. Choose the file again.", null)
        backupResult = null
        backupBytes = null
        stop()
        permissionResult?.error("CANCELLED", "Activity closed", null)
        permissionResult = null
        if (Build.VERSION.SDK_INT >= 27) channel?.close()
        io.shutdownNow()
        watchdog.shutdownNow()
        super.onDestroy()
    }
}
