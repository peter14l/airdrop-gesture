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
            val baseOptions = BaseOptions.builder()
                .setDelegate(Delegate.GPU)
                .setModelAssetPath(MODEL_NAME)
                .build()

            val options = GestureRecognizer.GestureRecognizerOptions.builder()
                .setBaseOptions(baseOptions)
                .setRunningMode(RunningMode.LIVE_STREAM)
                .setResultListener(this::onResult)
                .setErrorListener(this::onError)
                .build()

            gestureRecognizer = GestureRecognizer.createFromOptions(activity, options)
            Log.d(TAG, "MediaPipe Gesture Recognizer initialized successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize Gesture Recognizer: ${e.message}", e)
            isRunning = false
        }
    }

    private fun startCamera() {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(activity)
        cameraProviderFuture.addListener({
            try {
                cameraProvider = cameraProviderFuture.get()

                val cameraSelector = CameraSelector.DEFAULT_FRONT_CAMERA

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
                // activity IS a LifecycleOwner — CameraX will follow its lifecycle
                cameraProvider?.bindToLifecycle(
                    activity as LifecycleOwner,
                    cameraSelector,
                    imageAnalysis
                )
                Log.d(TAG, "CameraX started and bound to activity lifecycle.")
            } catch (e: Exception) {
                Log.e(TAG, "CameraX startup failed: ${e.message}", e)
            }
        }, ContextCompat.getMainExecutor(activity))
    }

    private fun processImageProxy(imageProxy: ImageProxy) {
        if (!isRunning || gestureRecognizer == null) {
            imageProxy.close()
            return
        }
        try {
            val bitmap = imageProxy.toBitmap()
            val mpImage = BitmapImageBuilder(bitmap).build()
            val timestampMs = imageProxy.imageInfo.timestamp / 1_000_000
            gestureRecognizer?.recognizeAsync(mpImage, timestampMs)
        } catch (e: Exception) {
            Log.e(TAG, "Error processing frame: ${e.message}")
        } finally {
            imageProxy.close()
        }
    }

    // Legacy path — no-op now that CameraX feeds frames directly
    fun processFrame(imageData: ByteArray, width: Int, height: Int, timestampMs: Long) {}

    private fun onResult(result: GestureRecognizerResult, image: com.google.mediapipe.framework.image.MPImage) {
        if (result.gestures().isNotEmpty()) {
            val gesture = result.gestures()[0][0].categoryName()
            Log.d(TAG, "Gesture recognized: $gesture")
            when (gesture) {
                "Closed_Fist" -> emitGesture("TRIGGER_GRAB")
                "Open_Palm"   -> emitGesture("TRIGGER_DROP")
            }
        }
    }

    private fun onError(error: RuntimeException) {
        Log.e(TAG, "MediaPipe error: ${error.message}", error)
    }

    private fun emitGesture(trigger: String) {
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            methodChannel.invokeMethod(trigger, null)
        }
    }
}
