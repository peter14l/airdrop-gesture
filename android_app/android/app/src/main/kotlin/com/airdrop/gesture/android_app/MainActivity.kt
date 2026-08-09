package com.airdrop.gesture.android_app

import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Handler
import android.os.Looper
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity(), SensorEventListener {
    private val CHANNEL = "com.airdrop.gesture/vision"
    private var gestureHelper: GestureRecognizerHelper? = null
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
        gestureHelper = GestureRecognizerHelper(applicationContext, channel)
        
        sensorManager = getSystemService(SENSOR_SERVICE) as SensorManager
        accelerometer = sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        proximity = sensorManager?.getDefaultSensor(Sensor.TYPE_PROXIMITY)

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startVisionPipeline" -> {
                    startVisionPipeline()
                    result.success(true)
                }
                "stopVisionPipeline" -> {
                    stopVisionPipeline()
                    result.success(true)
                }
                "processFrame" -> {
                    val frameBytes = call.argument<ByteArray>("bytes")
                    val width = call.argument<Int>("width") ?: 360
                    val height = call.argument<Int>("height") ?: 640
                    val timestamp = call.argument<Long>("timestamp") ?: System.currentTimeMillis()
                    if (frameBytes != null) {
                        gestureHelper?.processFrame(frameBytes, width, height, timestamp)
                        resetTimeoutTimer()
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
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
        autoKillHandler.postDelayed(autoKillRunnable, 8000) // Auto-kill after 8 seconds
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
        
        // Gated wake triggers on orientation shift or physical proximity
        if (event.sensor.type == Sensor.TYPE_ACCELEROMETER) {
            val zValue = event.values[2]
            // Screen tilts up/down trigger check
            if (zValue > 8.0) {
                startVisionPipeline()
            }
        } else if (event.sensor.type == Sensor.TYPE_PROXIMITY) {
            val distance = event.values[0]
            if (distance < 5.0) {
                startVisionPipeline()
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    override fun onDestroy() {
        super.onDestroy()
        stopVisionPipeline()
    }
}
