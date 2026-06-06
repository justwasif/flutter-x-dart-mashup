package com.example.console

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothHidDevice
import android.bluetooth.BluetoothHidDeviceAppQosSettings
import android.bluetooth.BluetoothHidDeviceAppSdpSettings
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val channelName = "hid_gamepad"
    private val requestCodeBluetooth = 4071
    private val executor = Executors.newSingleThreadExecutor()
    private var channel: MethodChannel? = null

    private var bluetoothAdapter: BluetoothAdapter? = null
    private var hidDevice: BluetoothHidDevice? = null
    private var connectedHost: BluetoothDevice? = null
    private var isRegistered = false

    // BUG FIX 1: Track whether profile proxy is ready before using it.
    // Previously, start() could be called before onServiceConnected fired,
    // leaving hidDevice null and silently failing.
    private var profileReady = false
    private var pendingStartResult: MethodChannel.Result? = null

    private val profileListener = object : BluetoothProfile.ServiceListener {
        override fun onServiceConnected(profile: Int, proxy: BluetoothProfile) {
            if (profile == BluetoothProfile.HID_DEVICE) {
                hidDevice = proxy as BluetoothHidDevice
                profileReady = true

                // BUG FIX 1 (cont): If Flutter called start() before the profile
                // was ready, we deferred it. Fulfil it now.
                pendingStartResult?.let { result ->
                    pendingStartResult = null
                    startHid(result)
                }
            }
        }

        override fun onServiceDisconnected(profile: Int) {
            if (profile == BluetoothProfile.HID_DEVICE) {
                hidDevice = null
                connectedHost = null
                isRegistered = false
                profileReady = false
            }
        }
    }

    private val hidCallback = object : BluetoothHidDevice.Callback() {
        override fun onAppStatusChanged(pluggedDevice: BluetoothDevice?, registered: Boolean) {
            isRegistered = registered
            // BUG FIX 2: Only update connectedHost from onAppStatusChanged if a device
            // is actually plugged in. Previously this overwrote a good connection.
            if (registered && pluggedDevice != null) {
                connectedHost = pluggedDevice
            } else if (!registered) {
                connectedHost = null
            }
            sendStatus()
        }

        override fun onConnectionStateChanged(device: BluetoothDevice?, state: Int) {
            connectedHost = if (state == BluetoothProfile.STATE_CONNECTED) device else null
            sendStatus()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // BUG FIX 3: Guard against a null BluetoothManager (e.g. emulator with no BT).
        val manager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        bluetoothAdapter = manager?.adapter

        bluetoothAdapter?.getProfileProxy(this, profileListener, BluetoothProfile.HID_DEVICE)

        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> result.success(
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && bluetoothAdapter != null
                )
                "requestPermissions" -> result.success(requestBluetoothPermissions())
                "openBluetoothSettings" -> {
                    startActivity(Intent(android.provider.Settings.ACTION_BLUETOOTH_SETTINGS))
                    result.success(true)
                }
                "start" -> {
                    if (!profileReady) {
                        // Profile proxy not yet connected — defer until it is.
                        pendingStartResult = result
                    } else {
                        startHid(result)
                    }
                }
                "stop" -> stopHid(result)
                "devices" -> result.success(bondedDevices())
                "connect" -> connect(call, result)
                "sendReport" -> sendReport(call, result)
                "status" -> result.success(statusMap())
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        stopHid(null)
        bluetoothAdapter?.closeProfileProxy(BluetoothProfile.HID_DEVICE, hidDevice)
        executor.shutdown()
        super.onDestroy()
    }

    private fun requestBluetoothPermissions(): Boolean {
        val permissions = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            permissions += Manifest.permission.BLUETOOTH_CONNECT
            permissions += Manifest.permission.BLUETOOTH_SCAN
            permissions += Manifest.permission.BLUETOOTH_ADVERTISE
        } else {
            permissions += Manifest.permission.ACCESS_FINE_LOCATION
        }

        val missing = permissions.filter {
            checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isNotEmpty()) {
            requestPermissions(missing.toTypedArray(), requestCodeBluetooth)
            return false
        }
        return true
    }

    @SuppressLint("MissingPermission")
    private fun startHid(result: MethodChannel.Result?) {
        if (!requestBluetoothPermissions()) {
            result?.success(false)
            return
        }

        val adapter = bluetoothAdapter
        val device = hidDevice

        // BUG FIX 4: Cleaner guard — each condition returns its own error message.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            result?.error("unsupported", "Android 9+ is required for Bluetooth HID Device.", null)
            return
        }
        if (adapter == null) {
            result?.error("unsupported", "No Bluetooth adapter found on this device.", null)
            return
        }
        if (device == null) {
            // Should not happen after the deferred-start fix, but guard anyway.
            result?.error("not_ready", "HID Device profile not ready yet. Try again.", null)
            return
        }
        if (!adapter.isEnabled) {
            result?.error("bluetooth_off", "Please turn Bluetooth on before starting HID mode.", null)
            return
        }
        if (isRegistered) {
            result?.success(true)
            return
        }

        val sdp = BluetoothHidDeviceAppSdpSettings(
            "Flutter HID Gamepad",
            "Low-latency virtual Bluetooth game controller",
            "flutter_learning",
            0x08.toByte(),
            gamepadDescriptor
        )
        val inQos = BluetoothHidDeviceAppQosSettings(
            BluetoothHidDeviceAppQosSettings.SERVICE_BEST_EFFORT,
            800, 9, 0, 11250, 11250
        )

        val ok = device.registerApp(sdp, inQos, null, executor, hidCallback)
        result?.success(ok)
    }

    @SuppressLint("MissingPermission")
    private fun stopHid(result: MethodChannel.Result?) {
        hidDevice?.unregisterApp()
        connectedHost = null
        isRegistered = false
        result?.success(true)
    }

    @SuppressLint("MissingPermission")
    private fun bondedDevices(): List<Map<String, String>> {
        // BUG FIX 5: Guard against Bluetooth being off — bondedDevices throws
        // IllegalStateException if the adapter is disabled.
        if (!requestBluetoothPermissions()) return emptyList()
        if (bluetoothAdapter?.isEnabled != true) return emptyList()

        return try {
            bluetoothAdapter?.bondedDevices?.map {
                mapOf(
                    "name" to (it.name ?: "Unknown device"),
                    "address" to it.address
                )
            } ?: emptyList()
        } catch (e: Exception) {
            emptyList()
        }
    }

    @SuppressLint("MissingPermission")
    private fun connect(call: MethodCall, result: MethodChannel.Result) {
        if (!requestBluetoothPermissions()) {
            result.success(false)
            return
        }

        // BUG FIX 6: hidDevice could be null here if profile disconnected unexpectedly.
        val hid = hidDevice
        if (hid == null) {
            result.error("not_ready", "HID Device profile is not available.", null)
            return
        }

        val address = call.argument<String>("address")
        if (address.isNullOrBlank()) {
            result.error("invalid_address", "No device address provided.", null)
            return
        }

        val device = try {
            bluetoothAdapter?.bondedDevices?.firstOrNull { it.address == address }
        } catch (e: Exception) {
            null
        }

        if (device == null) {
            result.error("not_bonded", "Pair the desktop first in Bluetooth settings, then retry.", null)
            return
        }

        result.success(hid.connect(device) == true)
    }

    @SuppressLint("MissingPermission")
    private fun sendReport(call: MethodCall, result: MethodChannel.Result) {
        val host = connectedHost
        if (host == null) {
            // BUG FIX 7: Return false (not an error crash) so Flutter can handle it gracefully.
            result.success(false)
            return
        }

        // BUG FIX 8: Safely coerce each axis value — previously could panic on bad input.
        val buttons = (call.argument<Int>("buttons") ?: 0).and(0xFFFF)
        val hat     = (call.argument<Int>("hat") ?: 8).and(0x0F)
        val lx      = (call.argument<Int>("lx") ?: 0).coerceIn(-127, 127)
        val ly      = (call.argument<Int>("ly") ?: 0).coerceIn(-127, 127)
        val rx      = (call.argument<Int>("rx") ?: 0).coerceIn(-127, 127)
        val ry      = (call.argument<Int>("ry") ?: 0).coerceIn(-127, 127)

        val report = byteArrayOf(
            (buttons and 0xff).toByte(),
            ((buttons shr 8) and 0xff).toByte(),
            hat.toByte(),
            lx.toByte(),
            ly.toByte(),
            rx.toByte(),
            ry.toByte()
        )

        val ok = try {
            hidDevice?.sendReport(host, 1, report) == true
        } catch (e: Exception) {
            false
        }
        result.success(ok)
    }

    private fun sendStatus() {
        channel?.invokeMethod("status", statusMap())
    }

    @SuppressLint("MissingPermission")
    private fun statusMap(): Map<String, Any?> = mapOf(
        "registered"  to isRegistered,
        "connected"   to (connectedHost != null),
        "hostName"    to try { connectedHost?.name } catch (e: Exception) { null },
        "hostAddress" to connectedHost?.address
    )

    private val gamepadDescriptor = byteArrayOf(
        0x05, 0x01, 0x09, 0x05, 0xA1.toByte(), 0x01, 0x85.toByte(), 0x01,
        0x05, 0x09, 0x19, 0x01, 0x29, 0x10, 0x15, 0x00, 0x25, 0x01,
        0x75, 0x01, 0x95.toByte(), 0x10, 0x81.toByte(), 0x02,
        0x05, 0x01, 0x09, 0x39, 0x15, 0x00, 0x25, 0x07, 0x35, 0x00,
        0x46, 0x3B, 0x01, 0x65, 0x14, 0x75, 0x04, 0x95.toByte(), 0x01,
        0x81.toByte(), 0x42, 0x65, 0x00, 0x75, 0x04, 0x95.toByte(), 0x01,
        0x81.toByte(), 0x03,
        0x09, 0x30, 0x09, 0x31, 0x09, 0x33, 0x09, 0x34, 0x15, 0x81.toByte(),
        0x25, 0x7F, 0x75, 0x08, 0x95.toByte(), 0x04, 0x81.toByte(), 0x02,
        0xC0.toByte()
    )
}