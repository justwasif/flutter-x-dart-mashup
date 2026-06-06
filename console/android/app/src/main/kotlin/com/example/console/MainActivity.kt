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

    private val profileListener = object : BluetoothProfile.ServiceListener {
        override fun onServiceConnected(profile: Int, proxy: BluetoothProfile) {
            if (profile == BluetoothProfile.HID_DEVICE) {
                hidDevice = proxy as BluetoothHidDevice
            }
        }

        override fun onServiceDisconnected(profile: Int) {
            if (profile == BluetoothProfile.HID_DEVICE) {
                hidDevice = null
                connectedHost = null
                isRegistered = false
            }
        }
    }

    private val hidCallback = object : BluetoothHidDevice.Callback() {
        override fun onAppStatusChanged(pluggedDevice: BluetoothDevice?, registered: Boolean) {
            isRegistered = registered
            connectedHost = pluggedDevice
            sendStatus()
        }

        override fun onConnectionStateChanged(device: BluetoothDevice?, state: Int) {
            connectedHost = if (state == BluetoothProfile.STATE_CONNECTED) device else null
            sendStatus()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        bluetoothAdapter = getSystemService(BluetoothManager::class.java)?.adapter
        bluetoothAdapter?.getProfileProxy(this, profileListener, BluetoothProfile.HID_DEVICE)

        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel?.setMethodCallHandler {
            call,
            result ->
            when (call.method) {
                "isSupported" -> result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && bluetoothAdapter != null)
                "requestPermissions" -> result.success(requestBluetoothPermissions())
                "openBluetoothSettings" -> {
                    startActivity(Intent(android.provider.Settings.ACTION_BLUETOOTH_SETTINGS))
                    result.success(true)
                }
                "start" -> startHid(result)
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
        if (adapter == null || device == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            result?.error("unsupported", "Bluetooth HID Device is not available on this phone.", null)
            return
        }
        if (!adapter.isEnabled) {
            result?.error("bluetooth_off", "Turn Bluetooth on before starting HID mode.", null)
            return
        }
        if (isRegistered) {
            result?.success(true)
            return
        }

        val sdp = BluetoothHidDeviceAppSdpSettings(
            "Flutter HID Gamepad",
            "Low-latency virtual Bluetooth game controller",
            "flutter_learnig",
            0x08.toByte(),
            gamepadDescriptor
        )
        val inQos = BluetoothHidDeviceAppQosSettings(
            BluetoothHidDeviceAppQosSettings.SERVICE_BEST_EFFORT,
            800,
            9,
            0,
            11250,
            11250
        )

        result?.success(device.registerApp(sdp, inQos, null, executor, hidCallback))
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
        if (!requestBluetoothPermissions()) return emptyList()
        return bluetoothAdapter?.bondedDevices?.map {
            mapOf(
                "name" to (it.name ?: "Unknown device"),
                "address" to it.address
            )
        } ?: emptyList()
    }

    @SuppressLint("MissingPermission")
    private fun connect(call: MethodCall, result: MethodChannel.Result) {
        if (!requestBluetoothPermissions()) {
            result.success(false)
            return
        }
        val address = call.argument<String>("address")
        val device = bluetoothAdapter?.bondedDevices?.firstOrNull { it.address == address }
        if (device == null) {
            result.error("not_bonded", "Pair the desktop first, then retry.", null)
            return
        }
        result.success(hidDevice?.connect(device) == true)
    }

    @SuppressLint("MissingPermission")
    private fun sendReport(call: MethodCall, result: MethodChannel.Result) {
        val buttons = call.argument<Int>("buttons") ?: 0
        val hat = call.argument<Int>("hat") ?: 8
        val lx = (call.argument<Int>("lx") ?: 0).coerceIn(-127, 127)
        val ly = (call.argument<Int>("ly") ?: 0).coerceIn(-127, 127)
        val rx = (call.argument<Int>("rx") ?: 0).coerceIn(-127, 127)
        val ry = (call.argument<Int>("ry") ?: 0).coerceIn(-127, 127)
        val host = connectedHost

        if (host == null) {
            result.success(false)
            return
        }

        val report = byteArrayOf(
            (buttons and 0xff).toByte(),
            ((buttons shr 8) and 0xff).toByte(),
            (hat and 0x0f).toByte(),
            lx.toByte(),
            ly.toByte(),
            rx.toByte(),
            ry.toByte()
        )
        result.success(hidDevice?.sendReport(host, 1, report) == true)
    }

    private fun sendStatus() {
        channel?.invokeMethod("status", statusMap())
    }

    @SuppressLint("MissingPermission")
    private fun statusMap(): Map<String, Any?> = mapOf(
        "registered" to isRegistered,
        "connected" to (connectedHost != null),
        "hostName" to connectedHost?.name,
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
