package dev.localchat.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.wifi.p2p.WifiP2pConfig
import android.net.wifi.p2p.WifiP2pManager
import android.net.wifi.p2p.nsd.WifiP2pDnsSdServiceInfo
import android.net.wifi.p2p.nsd.WifiP2pDnsSdServiceRequest
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.nio.charset.StandardCharsets
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/** Dedicated hosted-group transport. Crypto and membership stay in Dart. */
class GroupTransport(private val context: Context, messenger: BinaryMessenger,
    private val access: () -> Unit,
    private val closed: (Int, String) -> Unit,
    private val holdFrame: (Int, String) -> Boolean) : EventChannel.StreamHandler {
    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newCachedThreadPool()
    private val watchdog = Executors.newSingleThreadScheduledExecutor()
    private val p2p = context.getSystemService(WifiP2pManager::class.java)
    private var channel: WifiP2pManager.Channel? = null
    private var sink: EventChannel.EventSink? = null
    private var registered = false
    private val epoch = AtomicInteger(0)
    private val ids = AtomicInteger(0)
    @Volatile private var running = false
    @Volatile private var host = false
    @Volatile private var listener: ServerSocket? = null
    @Volatile private var connecting: Socket? = null
    private var starting = false
    private var formed = false
    private var scanEnd: Runnable? = null
    private val peers = linkedMapOf<String, Map<String, String>>()
    private class Link(val socket: Socket, val epoch: Int) {
        val output = DataOutputStream(BufferedOutputStream(socket.getOutputStream()))
        val writer = Any()
    }
    private val links = ConcurrentHashMap<String, Link>()
    // Direct socket generations are nonnegative; negative room generations
    // isolate the shared foreground-service lease across both transports.
    private fun backgroundGeneration() = -(epoch.get() + 1)
    fun backgroundEligible(token: Int, admitted: List<String>): Boolean =
        running && token == backgroundGeneration() && admitted.any {
            links[it]?.let { link -> link.epoch == epoch.get() && !link.socket.isClosed } == true
        } && runCatching { access() }.isSuccess
    init {
        EventChannel(messenger, "dev.localchat/group_events").setStreamHandler(this)
        MethodChannel(messenger, "dev.localchat/groups").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "host", "discover" -> {
                        access()
                        val name = call.argument<String>("name") ?: "LocalChat user"
                        require(name.isNotBlank() && name.length <= 32)
                        val title = call.argument<String>("title") ?: "Group"
                        require(title.isNotBlank() && title.length <= 64)
                        begin(call.method == "host", name, title, result)
                    }
                    "join" -> {
                        access()
                        require(running && !host && !starting && links.isEmpty()) { "Find a group first" }
                        val address = call.argument<String>("address") ?: error("Missing host")
                        require(peers.containsKey(address)) { "Host no longer listed. Find groups again." }
                        p2p!!.connect(channel!!, WifiP2pConfig().apply {
                            deviceAddress = address; groupOwnerIntent = 0
                        }, action(result))
                    }
                    "send" -> {
                        val id = call.argument<String>("link") ?: error("Missing link")
                        val link = links[id] ?: error("Member disconnected")
                        val bytes = (call.argument<String>("frame") ?: error("Missing frame")).toByteArray(StandardCharsets.UTF_8)
                        require(bytes.size in 1..65536)
                        io.execute {
                            try {
                                synchronized(link.writer) {
                                    check(links[id] === link && link.epoch == epoch.get())
                                    val deadline = watchdog.schedule({ link.socket.runCatching { close() } }, 15, TimeUnit.SECONDS)
                                    try { link.output.writeInt(bytes.size); link.output.write(bytes); link.output.flush() }
                                    finally { deadline.cancel(false) }
                                }
                                main.post { result.success(null) }
                            } catch (_: Exception) {
                                main.post { drop(id); result.error("GROUP_WRITE", "Member disconnected", null) }
                            }
                        }
                    }
                    "close" -> { call.argument<String>("link")?.let { drop(it) }; result.success(null) }
                    "stop" -> { stop(); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (_: SecurityException) { result.error("PERMISSION_DENIED", "Allow Nearby permission in Android Settings", null) }
            catch (e: Exception) { result.error("GROUP_TRANSPORT", e.message ?: "Group transport failed", null) }
        }
    }
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sink = events }
    override fun onCancel(arguments: Any?) { sink = null }
    private fun emit(type: String, vararg fields: Pair<String, Any?>) { sink?.success(mapOf("type" to type, *fields)) }
    private fun action(result: MethodChannel.Result, done: () -> Unit = {}): WifiP2pManager.ActionListener = object : WifiP2pManager.ActionListener {
        override fun onSuccess() { done(); result.success(null) }
        override fun onFailure(reason: Int) { result.error("GROUP_P2P", "Wi-Fi Direct could not complete this action ($reason). Try again.", null) }
    }
    private fun begin(asHost: Boolean, name: String, title: String, result: MethodChannel.Result) {
        stop()
        check(p2p != null) { "Wi-Fi Direct unavailable" }
        val token = epoch.get()
        channel = p2p.initialize(context, main.looper) {
            if (token == epoch.get() && running) { stop("lost"); emit("stopped") }
        }
        check(channel != null) { "Wi-Fi Direct channel unavailable" }
        running = true; host = asHost
        val filter = IntentFilter().apply {
            addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION)
        }
        if (Build.VERSION.SDK_INT >= 33) context.registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
        else context.registerReceiver(receiver, filter)
        registered = true
        // Drain an earlier direct/group radio session before creating/discovering.
        val next = {
            if (token != epoch.get() || !running) result.error("CANCELLED", "Group stopped", null)
            else try {
                access()
                if (asHost) advertise(token, name, title, result) else discover(token, result)
            } catch (_: Exception) { stop(); result.error("GROUP_ACCESS", "Check Wi-Fi and Nearby permission", null) }
        }
        p2p.removeGroup(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() { next() }
            override fun onFailure(reason: Int) { next() } // No existing group is normal.
        })
    }
    private fun advertise(token: Int, name: String, title: String, result: MethodChannel.Result) {
        val service = WifiP2pDnsSdServiceInfo.newInstance("localchat-group", "_localchatg._tcp",
            mapOf("app" to "localchat-group", "v" to "1", "name" to name, "title" to title))
        p2p!!.addLocalService(channel!!, service, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                if (token != epoch.get()) { result.error("CANCELLED", "Group stopped", null); return }
                try { access(); p2p.createGroup(channel!!, action(result) { checkInfo(token) }) }
                catch (_: Exception) { result.error("GROUP_ACCESS", "Check Wi-Fi and permission", null) }
            }
            override fun onFailure(reason: Int) { result.error("GROUP_ADVERTISE", "Could not advertise group ($reason)", null) }
        })
    }
    private fun discover(token: Int, result: MethodChannel.Result) {
        p2p!!.setDnsSdResponseListeners(channel!!, { _, _, _ -> }, { domain, record, device ->
            if (token == epoch.get() && running && domain.contains("_localchatg._tcp") && record["app"] == "localchat-group" && record["v"] == "1") {
                peers[device.deviceAddress] = mapOf("address" to device.deviceAddress,
                    "name" to (record["name"]?.take(32) ?: "Group host"), "title" to (record["title"]?.take(64) ?: "Nearby group"))
                emit("peers", "peers" to peers.values.toList())
            }
        })
        val request = WifiP2pDnsSdServiceRequest.newInstance("_localchatg._tcp")
        p2p.addServiceRequest(channel!!, request, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                if (token != epoch.get()) { result.error("CANCELLED", "Discovery stopped", null); return }
                try { access(); p2p.discoverServices(channel!!, action(result) {
                    scanEnd = Runnable {
                        if (token == epoch.get()) {
                            runCatching { p2p.stopPeerDiscovery(channel, null) }
                            emit("peers", "peers" to peers.values.toList())
                        }
                    }.also { main.postDelayed(it, 15000) }
                }) } catch (_: Exception) { result.error("GROUP_ACCESS", "Check Wi-Fi and permission", null) }
            }
            override fun onFailure(reason: Int) { result.error("GROUP_DISCOVERY", "Could not find hosts ($reason)", null) }
        })
    }
    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context, intent: Intent) {
            if (!running) return
            if (intent.action == WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION &&
                intent.getIntExtra(WifiP2pManager.EXTRA_WIFI_STATE, -1) != WifiP2pManager.WIFI_P2P_STATE_ENABLED) {
                stop("lost"); emit("stopped")
            } else if (intent.action == WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION) checkInfo(epoch.get())
        }
    }
    private fun checkInfo(token: Int) {
        try {
            access()
            p2p?.requestConnectionInfo(channel) { info ->
                if (token != epoch.get() || !running) return@requestConnectionInfo
                if (!info.groupFormed) {
                    if (formed) { stop("lost"); emit("stopped") }
                    return@requestConnectionInfo
                }
                formed = true
                if (info.isGroupOwner != host) { stop("lost"); emit("error"); return@requestConnectionInfo }
                if (!starting && listener == null && (host || links.isEmpty())) {
                    starting = true
                    val address = info.groupOwnerAddress?.hostAddress
                    io.execute { if (host) accept(token) else connect(token, address) }
                }
            }
        } catch (_: Exception) { stop("lost"); emit("stopped") }
    }
    private fun accept(token: Int) {
        try {
            val server = ServerSocket().apply { reuseAddress = true; bind(InetSocketAddress(45874)) }
            synchronized(this) { if (token != epoch.get()) { server.close(); return }; listener = server }
            while (token == epoch.get() && running) {
                val socket = server.accept()
                if (links.size >= 7 || token != epoch.get()) { socket.close(); continue }
                attach(token, socket)
            }
        } catch (_: Exception) { main.post { if (token == epoch.get()) { stop("lost"); emit("error") } } }
    }
    private fun connect(token: Int, address: String?) {
        var candidate: Socket? = null
        try {
            require(address != null)
            for (attempt in 0 until 15) {
                if (token != epoch.get()) return
                val socket = Socket(); connecting = socket
                try { socket.connect(InetSocketAddress(address, 45874), 2000); candidate = socket; break }
                catch (_: Exception) { socket.close(); Thread.sleep(400) }
                finally { if (connecting === socket) connecting = null }
            }
            attach(token, candidate ?: error("Host unavailable"))
        } catch (_: Exception) { candidate?.runCatching { close() }; main.post { if (token == epoch.get()) { stop("lost"); emit("error") } } }
    }
    private fun attach(token: Int, socket: Socket) {
        socket.tcpNoDelay = true; socket.keepAlive = true
        val id = "$token-${ids.incrementAndGet()}"
        val link = Link(socket, token)
        synchronized(this) { if (token != epoch.get()) { socket.close(); return }; links[id] = link }
        main.post { if (links[id] === link) emit("connected", "link" to id, "generation" to -(token + 1)) }
        io.execute {
            try {
                val input = DataInputStream(BufferedInputStream(socket.getInputStream()))
                while (token == epoch.get() && links[id] === link) {
                    socket.soTimeout = 0
                    val first = input.read(); if (first < 0) break
                    socket.soTimeout = 15000
                    val deadline = watchdog.schedule({ socket.runCatching { close() } }, 15, TimeUnit.SECONDS)
                    val frame = try {
                        val length = (first shl 24) or (input.readUnsignedByte() shl 16) or (input.readUnsignedByte() shl 8) or input.readUnsignedByte()
                        require(length in 1..65536)
                        val bytes = ByteArray(length); input.readFully(bytes)
                        StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString()
                    } finally { deadline.cancel(false) }
                    val held = holdFrame(-(token + 1), id)
                    main.post {
                        if (links[id] === link) emit("frame", "link" to id, "frame" to frame,
                            "generation" to -(token + 1), "held" to held)
                        else if (held) ConnectionService.finishFrame(-(token + 1))
                    }
                }
            } catch (_: Exception) { /* Only this member's link ends. */ }
            finally { main.post { if (links[id] === link) drop(id) } }
        }
    }
    private fun drop(id: String) {
        val link = links.remove(id) ?: return
        link.socket.runCatching { close() }
        closed(backgroundGeneration(), "member")
        emit("disconnected", "link" to id)
        if (!host) { stop(); emit("stopped") }
    }
    fun stop(reason: String = "disconnected") {
        closed(backgroundGeneration(), reason)
        synchronized(this) {
            epoch.incrementAndGet(); running = false
            listener?.runCatching { close() }; listener = null
            connecting?.runCatching { close() }; connecting = null
            for (link in links.values) link.socket.runCatching { close() }
            links.clear(); starting = false; formed = false; peers.clear()
        }
        scanEnd?.let { main.removeCallbacks(it) }; scanEnd = null
        if (channel != null) {
            runCatching { p2p?.cancelConnect(channel, null); p2p?.stopPeerDiscovery(channel, null)
                p2p?.clearLocalServices(channel, null); p2p?.clearServiceRequests(channel, null); p2p?.removeGroup(channel, null) }
            if (Build.VERSION.SDK_INT >= 27) channel?.close()
            channel = null
        }
        if (registered) { context.unregisterReceiver(receiver); registered = false }
    }
    fun dispose() { stop(); sink = null; io.shutdownNow(); watchdog.shutdownNow() }
}
