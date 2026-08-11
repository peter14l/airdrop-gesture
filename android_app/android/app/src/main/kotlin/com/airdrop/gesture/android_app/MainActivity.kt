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
                "processFrame" -> {
                    // Frames are now fed by CameraX directly; this path is a no-op
                    result.success(true)
                }
                else -> result.notImplemented()
            }
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
        resetTimeoutTimer()
    }

    private fun stopVisionPipeline() {
        gestureHelper?.stop()
        unregisterSensors()
        autoKillHandler.removeCallbacks(autoKillRunnable)
    }

    private fun resetTimeoutTimer() {
        autoKillHandler.removeCallbacks(autoKillRunnable)
        autoKillHandler.postDelayed(autoKillRunnable, 30_000) // Auto-kill after 30 seconds idle
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
