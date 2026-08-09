package com.airdrop.gesture.android_app

import android.content.Context
import android.util.Log
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.gesturerecognizer.GestureRecognizer
import com.google.mediapipe.tasks.vision.gesturerecognizer.GestureRecognizerResult
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class GestureRecognizerHelper(
    private val context: Context,
    private val methodChannel: MethodChannel
) {
    private var gestureRecognizer: GestureRecognizer? = null
    private var executor: ExecutorService? = null
    private var isProcessing = false

    companion object {
        private const val TAG = "GestureRecognizerHelper"
        private const val MODEL_NAME = "gesture_recognizer.task"
    }

    fun start() {
        if (isProcessing) return
        isProcessing = true
        executor = Executors.newSingleThreadExecutor()
        executor?.execute {
            try {
                setupGestureRecognizer()
                Log.d(TAG, "MediaPipe Gesture Recognizer initialized successfully")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to initialize Gesture Recognizer: ${e.message}", e)
                isProcessing = false
            }
        }
    }

    fun stop() {
        isProcessing = false
        executor?.execute {
            try {
                gestureRecognizer?.close()
                gestureRecognizer = null
                Log.d(TAG, "MediaPipe Gesture Recognizer closed cleanly")
            } catch (e: Exception) {
                Log.e(TAG, "Error closing Gesture Recognizer: ${e.message}", e)
            }
        }
        executor?.shutdown()
        try {
            if (executor?.awaitTermination(800, TimeUnit.MILLISECONDS) == false) {
                executor?.shutdownNow()
            }
        } catch (e: InterruptedException) {
            executor?.shutdownNow()
        }
        executor = null
    }

    private fun setupGestureRecognizer() {
        val baseOptionsBuilder = BaseOptions.builder()
            .setDelegate(Delegate.GPU)
            .setModelAssetPath(MODEL_NAME)

        val optionsBuilder = GestureRecognizer.GestureRecognizerOptions.builder()
            .setBaseOptions(baseOptionsBuilder.build())
            .setRunningMode(RunningMode.LIVE_STREAM)
            .setResultListener(this::onResult)
            .setErrorListener(this::onError)

        gestureRecognizer = GestureRecognizer.createFromOptions(context, optionsBuilder.build())
    }

    fun processFrame(imageData: ByteArray, width: Int, height: Int, timestampMs: Long) {
        if (!isProcessing || gestureRecognizer == null) return
        executor?.execute {
            try {
                // Downscaled 360p camera frame processing
                // Convert raw format to MP Image and recognize
                // For simulator / demo validation logic without direct camera hardware bindings:
                // We mock the recognition of PINCH / PALM based on simulated data or frame buffers.
                // In actual deployment, standard MediaPipe Image conversion goes here.
                
                // Demo simulated trigger logic based on raw frame analysis signature
                if (imageData.isNotEmpty()) {
                    val averageColor = imageData.map { it.toInt() and 0xFF }.average()
                    // Fist/Pinch trigger condition: average color lower bounds
                    if (averageColor < 80.0) {
                        emitGesture("TRIGGER_GRAB")
                    } else if (averageColor > 180.0) {
                        emitGesture("TRIGGER_DROP")
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error processing frame: ${e.message}")
            }
        }
    }

    private fun onResult(result: GestureRecognizerResult, image: com.google.mediapipe.framework.image.MPImage) {
        if (result.gestures().isNotEmpty()) {
            val gesture = result.gestures()[0][0].categoryName()
            Log.d(TAG, "Gesture recognized: $gesture")
            when (gesture) {
                "Closed_Fist", "Pinch" -> emitGesture("TRIGGER_GRAB")
                "Open_Palm" -> emitGesture("TRIGGER_DROP")
            }
        }
    }

    private fun onError(error: RuntimeException) {
        Log.e(TAG, "MediaPipe error: ${error.message}", error)
    }

    private fun emitGesture(trigger: String) {
        // Safe dispatch on Main Thread back to Flutter UI channel
        val handler = android.os.Handler(android.os.Looper.getMainLooper())
        handler.post {
            methodChannel.invokeMethod(trigger, null)
        }
    }
}
