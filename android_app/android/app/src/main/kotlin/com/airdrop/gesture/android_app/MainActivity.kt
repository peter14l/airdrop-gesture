package com.airdrop.gesture.android_app

import android.Manifest
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Handler
import android.os.Looper
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity(), SensorEventListener {
    private val CHANNEL = "com.airdrop.gesture/vision"
    private val CAMERA_PERMISSION_REQUEST_CODE = 1001
    private var gestureHelper: GestureRecognizerHelper? = null
    private var methodChannel: MethodChannel? = null
    private var sensorManager: SensorManager? = null
    private var accelerometer: Sensor? = null
    private var proximity: Sensor? = null

    private val autoKillHandler = Handler(Looper.getMainLooper())
    private val autoKillRunnable = Runnable {
        stopVisionPipeline()
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel = channel
        // Pass `this` (the Activity) — it implements LifecycleOwner, required by CameraX
        gestureHelper = GestureRecognizerHelper(this, channel)

        sensorManager = getSystemService(SENSOR_SERVICE) as SensorManager
        accelerometer = sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        proximity = sensorManager?.getDefaultSensor(Sensor.TYPE_PROXIMITY)

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startVisionPipeline" -> {
                    startVisionPipelineWithPermission()
                    result.success(true)
                }
                "stopVisionPipeline" -> {
                    stopVisionPipeline()
                    result.success(true)
                }
                "checkOverlayPermission" -> {
                    val hasOverlay = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                        android.provider.Settings.canDrawOverlays(this)
                    } else {
                        true
                    }
                    result.success(hasOverlay)
                }
                "requestOverlayPermission" -> {
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                        val intent = android.content.Intent(
                            android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            android.net.Uri.parse("package:$packageName")
                        )
                        startActivity(intent)
                    }
                    result.success(true)
                }
                "getSharedFile" -> {
                    val path = extractSharedFilePath(intent)
                    result.success(path)
                }
                "processFrame" -> {
                    // Frames are now fed by CameraX directly; this path is a no-op
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(newIntent: android.content.Intent) {
        super.onNewIntent(newIntent)
        setIntent(newIntent)
        val path = extractSharedFilePath(newIntent)
        if (path != null) {
            methodChannel?.invokeMethod("onSharedFileReceived", path)
        }
    }

    private fun extractSharedFilePath(inIntent: android.content.Intent?): String? {
        if (inIntent == null) return null
        if (inIntent.action == android.content.Intent.ACTION_SEND) {
            val uri = inIntent.getParcelableExtra<android.net.Uri>(android.content.Intent.EXTRA_STREAM)
            if (uri != null) {
                return copyUriToCache(uri)
            } else {
                val text = inIntent.getStringExtra(android.content.Intent.EXTRA_TEXT)
                if (text != null) return "text:$text"
            }
        }
        return null
    }

    private fun copyUriToCache(uri: android.net.Uri): String? {
        return try {
            val resolver = contentResolver
            val name = "shared_${System.currentTimeMillis()}"
            val tempFile = java.io.File(cacheDir, name)
            resolver.openInputStream(uri)?.use { input ->
                tempFile.outputStream().use { output ->
                    input.copyTo(output)
                }
            }
            tempFile.absolutePath
        } catch (e: Exception) {
            null
        }
    }

    private fun hasCameraPermission() =
        ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED

    private fun startVisionPipelineWithPermission() {
        if (hasCameraPermission()) {
            startVisionPipeline()
        } else {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.CAMERA),
                CAMERA_PERMISSION_REQUEST_CODE
            )
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == CAMERA_PERMISSION_REQUEST_CODE &&
            grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        ) {
            startVisionPipeline()
        }
    }

    private fun startVisionPipeline() {
        gestureHelper?.start()
        registerSensors()
    }

    private fun stopVisionPipeline() {
        gestureHelper?.stop()
        unregisterSensors()
        autoKillHandler.removeCallbacks(autoKillRunnable)
        runOnUiThread {
            methodChannel?.invokeMethod("onPipelineStopped", null)
        }
    }

    private fun resetTimeoutTimer() {
        // Keeps camera active while screen is in foreground
    }

    private fun registerSensors() {
        sensorManager?.registerListener(this, accelerometer, SensorManager.SENSOR_DELAY_NORMAL)
        sensorManager?.registerListener(this, proximity, SensorManager.SENSOR_DELAY_NORMAL)
    }

    private fun unregisterSensors() {
        sensorManager?.unregisterListener(this)
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event == null) return
        if (event.sensor.type == Sensor.TYPE_ACCELEROMETER) {
            val zValue = event.values[2]
            if (zValue > 8.0) startVisionPipelineWithPermission()
        } else if (event.sensor.type == Sensor.TYPE_PROXIMITY) {
            val distance = event.values[0]
            if (distance < 5.0) startVisionPipelineWithPermission()
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    override fun onDestroy() {
        super.onDestroy()
        stopVisionPipeline()
    }
}
