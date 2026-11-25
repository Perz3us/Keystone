// SPDX-License-Identifier: GPL-3.0-or-later

package com.perz3us.keystone

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.ViewGroup

class MainActivity : FlutterFragmentActivity() {
    private val PERMISSION_CHANNEL = "com.perz3us.keystone/local_network_permission"
    private val LIFECYCLE_CHANNEL = "com.perz3us.keystone/app_lifecycle"
    private val LOCAL_NETWORK_PERMISSION_CODE = 1001
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var multicastLock: android.net.wifi.WifiManager.MulticastLock? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        unlockHighRefreshRate()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LIFECYCLE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "exitApp" -> {
                    try {
                        moveTaskToBack(true)
                        finish()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("EXIT_ERROR", e.message, null)
                    }
                }
                "openWifiSettings" -> {
                    try {
                        startActivity(android.content.Intent(android.provider.Settings.ACTION_WIFI_SETTINGS))
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SETTINGS_ERROR", e.message, null)
                    }
                }
                "multicastLock" -> {
                    try {
                        val wifi = applicationContext.getSystemService(android.content.Context.WIFI_SERVICE) as android.net.wifi.WifiManager
                        val lock = multicastLock ?: wifi.createMulticastLock("keystone-discovery").also {
                            it.setReferenceCounted(false)
                            multicastLock = it
                        }
                        if (call.arguments == true) lock.acquire() else if (lock.isHeld) lock.release()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("MULTICAST_ERROR", e.message, null)
                    }
                }
                "moveTaskToBack" -> {
                    try {
                        val moved = moveTaskToBack(true)
                        result.success(moved)
                    } catch (e: Exception) {
                        result.error("MOVE_ERROR", e.message, null)
                    }
                }
                "tone" -> {
                    playTone(call.argument<Double>("hz") ?: 440.0, call.argument<Int>("ms") ?: 150)
                    result.success(null)
                }
                "abis" -> result.success(Build.SUPPORTED_ABIS.toList())
                "installApk" -> installApk(call.argument<String>("path")!!, call.argument<String>("sha256"), result)
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PERMISSION_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkLocalNetworkPermission" -> {
                    val status = checkLocalNetworkPermissionStatus()
                    result.success(status)
                }
                "requestLocalNetworkPermission" -> {
                    if (Build.VERSION.SDK_INT >= 37) {
                        val permission = "android.permission.ACCESS_LOCAL_NETWORK"
                        if (ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED) {
                            result.success(true)
                        } else {
                            pendingPermissionResult = result
                            ActivityCompat.requestPermissions(this, arrayOf(permission), LOCAL_NETWORK_PERMISSION_CODE)
                        }
                    } else {
                        result.success(true)
                    }
                }
                "openAppSettings" -> {
                    try {
                        val intent = android.content.Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                            data = android.net.Uri.fromParts("package", packageName, null)
                            addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SETTINGS_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    // Only the community flavor declares the provider and install permission;
    // elsewhere getUriForFile throws and the app falls back to the release page.
    private fun installApk(path: String, sha256: String?, result: MethodChannel.Result) {
        Thread {
            try {
                val file = java.io.File(path)
                if (sha256 != null) {
                    val digest = java.security.MessageDigest.getInstance("SHA-256")
                    file.inputStream().use { input ->
                        val buf = ByteArray(1 shl 16)
                        while (true) {
                            val n = input.read(buf)
                            if (n < 0) break
                            digest.update(buf, 0, n)
                        }
                    }
                    val got = digest.digest().joinToString("") { "%02x".format(it) }
                    if (!got.equals(sha256, ignoreCase = true)) {
                        file.delete()
                        runOnUiThread { result.error("BAD_HASH", "The download is damaged", null) }
                        return@Thread
                    }
                }
                val uri = androidx.core.content.FileProvider.getUriForFile(this, "$packageName.updates", file)
                val intent = android.content.Intent(android.content.Intent.ACTION_VIEW)
                    .setDataAndType(uri, "application/vnd.android.package-archive")
                    .addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION or android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                runOnUiThread {
                    try {
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("INSTALL_ERROR", e.message, null)
                    }
                }
            } catch (e: Exception) {
                runOnUiThread { result.error("INSTALL_ERROR", e.message, null) }
            }
        }.start()
    }

    private var tonePlaying = false

    private fun playTone(hz: Double, ms: Int) {
        if (tonePlaying) return
        var track: AudioTrack? = null
        try {
            val rate = 44100
            val n = rate * ms / 1000
            val fade = rate * 5 / 1000
            val pcm = ShortArray(n) {
                val edge = minOf(it, n - 1 - it).toDouble() / fade
                (Math.sin(2 * Math.PI * hz * it / rate) * Short.MAX_VALUE * 0.5 * minOf(1.0, edge)).toInt().toShort()
            }
            val t = AudioTrack.Builder()
                .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).build())
                .setAudioFormat(AudioFormat.Builder().setEncoding(AudioFormat.ENCODING_PCM_16BIT).setSampleRate(rate).setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
                .setBufferSizeInBytes(n * 2)
                .setTransferMode(AudioTrack.MODE_STATIC)
                .build()
            track = t
            if (t.write(pcm, 0, n) != n) {
                t.release()
                return
            }
            var released = false
            val done = {
                if (!released) {
                    released = true
                    t.release()
                    tonePlaying = false
                }
            }
            t.setPlaybackPositionUpdateListener(object : AudioTrack.OnPlaybackPositionUpdateListener {
                override fun onMarkerReached(track: AudioTrack?) = done()
                override fun onPeriodicNotification(track: AudioTrack?) {}
            }, android.os.Handler(mainLooper))
            t.setNotificationMarkerPosition(n)
            tonePlaying = true
            t.play()
            android.os.Handler(mainLooper).postDelayed(done, ms + 200L)
        } catch (_: Exception) {
            track?.release()
            tonePlaying = false
        }
    }

    private fun checkLocalNetworkPermissionStatus(): Boolean {
        return if (Build.VERSION.SDK_INT >= 37) {
            ContextCompat.checkSelfPermission(this, "android.permission.ACCESS_LOCAL_NETWORK") == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == LOCAL_NETWORK_PERMISSION_CODE) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
        }
    }

    override fun onPostCreate(savedInstanceState: Bundle?) {
        super.onPostCreate(savedInstanceState)
        setupScrollCaptureSupport()
    }

    override fun onResume() {
        super.onResume()
        unlockHighRefreshRate()
        setupScrollCaptureSupport()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            unlockHighRefreshRate()
            setupScrollCaptureSupport()
        }
    }

    private fun setupScrollCaptureSupport() {
        try {
            window.decorView.isScrollContainer = true
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                window.decorView.scrollCaptureHint = View.SCROLL_CAPTURE_HINT_INCLUDE
            }

            val contentView = findViewById<View>(android.R.id.content)
            contentView?.let { root ->
                root.isScrollContainer = true
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    root.scrollCaptureHint = View.SCROLL_CAPTURE_HINT_INCLUDE
                }
                if (root is ViewGroup) {
                    enableScrollCaptureRecursively(root)
                }
            }
        } catch (_: Exception) {
        }
    }

    private fun enableScrollCaptureRecursively(viewGroup: ViewGroup) {
        for (i in 0 until viewGroup.childCount) {
            val child = viewGroup.getChildAt(i)
            child.isScrollContainer = true
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                child.scrollCaptureHint = View.SCROLL_CAPTURE_HINT_INCLUDE
            }
            if (child is ViewGroup) {
                enableScrollCaptureRecursively(child)
            }
        }
    }

    private fun unlockHighRefreshRate() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                val display = this.display ?: return
                val currentMode = display.mode
                val supportedModes = display.supportedModes ?: return
                val maxMode = supportedModes
                    .filter { it.physicalWidth == currentMode.physicalWidth && it.physicalHeight == currentMode.physicalHeight }
                    .maxByOrNull { it.refreshRate }
                    ?: supportedModes.maxByOrNull { it.refreshRate }

                if (maxMode != null && window.attributes.preferredDisplayModeId != maxMode.modeId) {
                    val lp = window.attributes
                    lp.preferredDisplayModeId = maxMode.modeId
                    window.attributes = lp
                }
            } catch (_: Exception) {
            }
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                @Suppress("DEPRECATION")
                val display = windowManager.defaultDisplay ?: return
                val currentMode = display.mode
                val supportedModes = display.supportedModes ?: return
                val maxMode = supportedModes
                    .filter { it.physicalWidth == currentMode.physicalWidth && it.physicalHeight == currentMode.physicalHeight }
                    .maxByOrNull { it.refreshRate }
                    ?: supportedModes.maxByOrNull { it.refreshRate }

                if (maxMode != null && window.attributes.preferredDisplayModeId != maxMode.modeId) {
                    val lp = window.attributes
                    lp.preferredDisplayModeId = maxMode.modeId
                    window.attributes = lp
                }
            } catch (_: Exception) {
            }
        }
    }

    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        if (level >= android.content.ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW || level == android.content.ComponentCallbacks2.TRIM_MEMORY_UI_HIDDEN) {
            flutterEngine?.systemChannel?.sendMemoryPressureWarning()
        }
    }

    override fun onLowMemory() {
        super.onLowMemory()
        flutterEngine?.systemChannel?.sendMemoryPressureWarning()
    }
}
