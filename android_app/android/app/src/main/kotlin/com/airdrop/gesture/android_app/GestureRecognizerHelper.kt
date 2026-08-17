package com.airdrop.gesture.android_app

import android.util.Log
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.gesturerecognizer.GestureRecognizer
import com.google.mediapipe.tasks.vision.gesturerecognizer.GestureRecognizerResult
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class GestureRecognizerHelper(
    // Receive the Activity directly so CameraX has a valid LifecycleOwner
    private val activity: MainActivity,
    private val methodChannel: MethodChannel
) {
    private var gestureRecognizer: GestureRecognizer? = null
    private var cameraProvider: ProcessCameraProvider? = null
    private var imageAnalysis: ImageAnalysis? = null
    private val cameraExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private var isRunning = false

    companion object {
        private const val TAG = "GestureRecognizerHelper"
        private const val MODEL_NAME = "gesture_recognizer.task"
    }

    fun start() {
        if (isRunning) return
        isRunning = true
        setupGestureRecognizer()
        startCamera()
    }

    fun stop() {
        isRunning = false
        cameraProvider?.unbindAll()
        gestureRecognizer?.close()
        gestureRecognizer = null
        Log.d(TAG, "Camera and MediaPipe stopped.")
    }

    private fun setupGestureRecognizer() {
        try {
            // Try GPU delegate first, fallback to CPU if GPU delegate is unsupported on device
            var baseOptionsBuilder = BaseOptions.builder().setModelAssetPath(MODEL_NAME)
            try {
                baseOptionsBuilder = baseOptionsBuilder.setDelegate(Delegate.GPU)
            } catch (e: Exception) {
                baseOptionsBuilder = BaseOptions.builder().setModelAssetPath(MODEL_NAME).setDelegate(Delegate.CPU)
            }

            val options = GestureRecognizer.GestureRecognizerOptions.builder()
                .setBaseOptions(baseOptionsBuilder.build())
                .setRunningMode(RunningMode.LIVE_STREAM)
                .setMinHandDetectionConfidence(0.5f)
                .setMinHandPresenceConfidence(0.5f)
                .setMinTrackingConfidence(0.5f)
                .setResultListener(this::onResult)
                .setErrorListener(this::onError)
                .build()

            gestureRecognizer = GestureRecognizer.createFromOptions(activity, options)
            Log.d(TAG, "MediaPipe Gesture Recognizer initialized successfully")
        } catch (e: Exception) {
            Log.e(TAG, "GPU init failed, attempting CPU fallback: ${e.message}")
            try {
                val cpuOptions = GestureRecognizer.GestureRecognizerOptions.builder()
                    .setBaseOptions(BaseOptions.builder().setModelAssetPath(MODEL_NAME).setDelegate(Delegate.CPU).build())
                    .setRunningMode(RunningMode.LIVE_STREAM)
                    .setMinHandDetectionConfidence(0.5f)
                    .setMinHandPresenceConfidence(0.5f)
                    .setMinTrackingConfidence(0.5f)
                    .setResultListener(this::onResult)
                    .setErrorListener(this::onError)
                    .build()
                gestureRecognizer = GestureRecognizer.createFromOptions(activity, cpuOptions)
                Log.d(TAG, "MediaPipe CPU Gesture Recognizer initialized successfully")
            } catch (cpuEx: Exception) {
                Log.e(TAG, "Failed to initialize Gesture Recognizer on CPU: ${cpuEx.message}", cpuEx)
                isRunning = false
            }
        }
    }

    private fun startCamera() {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(activity)
        cameraProviderFuture.addListener({
            try {
                cameraProvider = cameraProviderFuture.get()

                var cameraSelector = CameraSelector.DEFAULT_FRONT_CAMERA
                if (cameraProvider?.hasCamera(CameraSelector.DEFAULT_FRONT_CAMERA) != true) {
                    Log.w(TAG, "Front camera not found, falling back to back camera.")
                    cameraSelector = CameraSelector.DEFAULT_BACK_CAMERA
                }

                imageAnalysis = ImageAnalysis.Builder()
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
                    .build()
                    .also { analysis ->
                        analysis.setAnalyzer(cameraExecutor) { imageProxy ->
                            processImageProxy(imageProxy)
                        }
                    }

                cameraProvider?.unbindAll()
                cameraProvider?.bindToLifecycle(
                    activity as LifecycleOwner,
                    cameraSelector,
                    imageAnalysis
                )
                Log.d(TAG, "CameraX successfully started and bound to activity lifecycle.")
            } catch (e: Exception) {
                Log.e(TAG, "CameraX startup failed: ${e.message}", e)
            }
        }, ContextCompat.getMainExecutor(activity))
    }

    private var lastFrameTime = 0L
    private val frameStreamIntervalMs = 33L // ~30 FPS live preview stream

    private fun processImageProxy(imageProxy: ImageProxy) {
        if (!isRunning) {
            imageProxy.close()
            return
        }
        try {
            val bitmap = imageProxy.toBitmap()
            val rotationDegrees = imageProxy.imageInfo.rotationDegrees

            // Rotate bitmap according to camera sensor orientation
            val matrix = android.graphics.Matrix()
            matrix.postRotate(rotationDegrees.toFloat())
            // Mirror horizontally since it's the front-facing camera
            matrix.postScale(-1f, 1f, bitmap.width / 2f, bitmap.height / 2f)

            val rotatedBitmap = android.graphics.Bitmap.createBitmap(
                bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true
            )

            // 1. ALWAYS Stream live camera preview frame to Flutter UI independently of MediaPipe
            val now = System.currentTimeMillis()
            if (now - lastFrameTime >= frameStreamIntervalMs) {
                lastFrameTime = now
                val scaled = android.graphics.Bitmap.createScaledBitmap(rotatedBitmap, 360, (360f * rotatedBitmap.height / rotatedBitmap.width).toInt(), false)
                val out = java.io.ByteArrayOutputStream()
                scaled.compress(android.graphics.Bitmap.CompressFormat.JPEG, 65, out)
                val jpegBytes = out.toByteArray()
                emitCameraFrame(jpegBytes)
            }

            // 2. Feed MediaPipe if initialized
            if (gestureRecognizer != null) {
                try {
                    val mpImage = BitmapImageBuilder(rotatedBitmap).build()
                    val timestampMs = imageProxy.imageInfo.timestamp / 1_000_000
                    gestureRecognizer?.recognizeAsync(mpImage, timestampMs)
                } catch (mpEx: Exception) {
                    Log.e(TAG, "MediaPipe recognition frame error: ${mpEx.message}")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error processing frame: ${e.message}")
        } finally {
            imageProxy.close()
        }
    }

    private fun emitCameraFrame(bytes: ByteArray) {
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            methodChannel.invokeMethod("onCameraFrame", bytes)
        }
    }

    private fun onResult(result: GestureRecognizerResult, image: com.google.mediapipe.framework.image.MPImage) {
        // Extract hand landmarks for live skeleton overlay
        if (result.landmarks().isNotEmpty()) {
            val handLandmarks = result.landmarks()[0]
            val landmarkPoints = ArrayList<Map<String, Double>>()
            for (lm in handLandmarks) {
                val pt = HashMap<String, Double>()
                pt["x"] = lm.x().toDouble()
                pt["y"] = lm.y().toDouble()
                pt["z"] = lm.z().toDouble()
                landmarkPoints.add(pt)
            }
            emitLandmarks(landmarkPoints)
        } else {
            emitLandmarks(emptyList())
        }

        if (result.gestures().isNotEmpty()) {
            val gesture = result.gestures()[0][0].categoryName()
            val score = result.gestures()[0][0].score()
            Log.d(TAG, "Gesture recognized: $gesture with score $score")

            // Send raw detected category for real-time UI display
            emitRawGesture(gesture)

            when (gesture) {
                "Closed_Fist" -> emitGesture("TRIGGER_GRAB")
                "Open_Palm"   -> emitGesture("TRIGGER_DROP")
            }
        } else {
            emitRawGesture("None")
        }
    }

    private fun onError(error: RuntimeException) {
        Log.e(TAG, "MediaPipe error: ${error.message}", error)
    }

    private fun emitLandmarks(landmarks: List<Map<String, Double>>) {
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            methodChannel.invokeMethod("onLandmarksDetected", landmarks)
        }
    }

    private fun emitRawGesture(gesture: String) {
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            methodChannel.invokeMethod("onGestureDetected", gesture)
        }
    }

    private fun emitGesture(trigger: String) {
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            methodChannel.invokeMethod(trigger, null)
        }
    }
}
