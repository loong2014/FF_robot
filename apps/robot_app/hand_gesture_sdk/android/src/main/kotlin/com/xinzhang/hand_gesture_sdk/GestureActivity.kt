package com.xinzhang.hand_gesture_sdk

import android.Manifest
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Matrix
import android.graphics.PointF
import android.os.Bundle
import android.os.SystemClock
import android.util.Size
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.components.containers.Category
import com.google.mediapipe.tasks.components.containers.NormalizedLandmark
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarker
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarkerResult
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarkerResult
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class GestureActivity : AppCompatActivity() {

    private lateinit var previewView: PreviewView
    private lateinit var skeletonOverlayView: SkeletonOverlayView
    private lateinit var statusLabel: TextView
    private lateinit var gestureLabel: TextView
    private lateinit var poseLabel: TextView

    private val cameraExecutor = Executors.newSingleThreadExecutor()
    private val modelExecutor = Executors.newSingleThreadExecutor()
    private val processingFrame = AtomicBoolean(false)

    private var cameraProvider: ProcessCameraProvider? = null
    private var handLandmarker: HandLandmarker? = null
    private var poseLandmarker: PoseLandmarker? = null
    private var lastStatusMessage = ""
    private var lastTimestampMs = 0L
    private var cameraStarted = false

    private val requestCameraPermission = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) {
            initializeRecognizersAndStart()
        } else {
            reportError("相机权限被拒绝")
            finish()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        GestureActivityRegistry.currentActivity = this
        setContentView(buildContentView())
        updateStatus("正在检查相机权限...")

        if (hasCameraPermission()) {
            initializeRecognizersAndStart()
        } else {
            requestCameraPermission.launch(Manifest.permission.CAMERA)
        }
    }

    override fun onBackPressed() {
        finish()
    }

    override fun onDestroy() {
        GestureActivityRegistry.currentActivity = null
        cameraProvider?.unbindAll()
        handLandmarker?.close()
        poseLandmarker?.close()
        cameraExecutor.shutdownNow()
        modelExecutor.shutdownNow()
        super.onDestroy()
    }

    private fun buildContentView(): FrameLayout {
        val root = FrameLayout(this)

        previewView = PreviewView(this).apply {
            implementationMode = PreviewView.ImplementationMode.COMPATIBLE
            scaleType = PreviewView.ScaleType.FILL_CENTER
        }
        root.addView(
            previewView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )

        skeletonOverlayView = SkeletonOverlayView(this).apply {
            setMirrorX(true)
        }
        root.addView(
            skeletonOverlayView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )

        val overlay = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(40, 72, 40, 40)
        }
        root.addView(
            overlay,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT
            )
        )

        statusLabel = TextView(this).apply {
            setTextColor(0xFFFFFFFF.toInt())
            textSize = 16f
            text = "正在准备..."
        }
        overlay.addView(statusLabel)

        gestureLabel = TextView(this).apply {
            setTextColor(0xFFFFFFFF.toInt())
            textSize = 28f
            text = "等待相机开启..."
        }
        overlay.addView(gestureLabel)

        poseLabel = TextView(this).apply {
            setTextColor(0xFFE0E0E0.toInt())
            textSize = 20f
            text = "等待动作识别..."
        }
        overlay.addView(poseLabel)

        val closeButton = Button(this).apply {
            text = "关闭"
            setOnClickListener { finish() }
        }
        overlay.addView(closeButton)

        return root
    }

    private fun hasCameraPermission(): Boolean {
        return ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun initializeRecognizersAndStart() {
        updateStatus("正在加载内置模型...")
        modelExecutor.execute {
            try {
                handLandmarker?.close()
                poseLandmarker?.close()
                handLandmarker = createHandLandmarker()
                poseLandmarker = createPoseLandmarker()
                runOnUiThread {
                    startCameraIfNeeded()
                }
            } catch (error: Exception) {
                reportError("识别器初始化失败：${error.localizedMessage ?: "unknown"}")
            }
        }
    }

    private fun createHandLandmarker(): HandLandmarker {
        val baseOptions = BaseOptions.builder()
            .setModelAssetPath(HAND_MODEL_ASSET_PATH)
            .build()
        val options = HandLandmarker.HandLandmarkerOptions.builder()
            .setBaseOptions(baseOptions)
            .setRunningMode(RunningMode.VIDEO)
            .setNumHands(1)
            .setMinHandDetectionConfidence(0.7f)
            .setMinHandPresenceConfidence(0.7f)
            .setMinTrackingConfidence(0.5f)
            .build()
        return HandLandmarker.createFromOptions(this, options)
    }

    private fun createPoseLandmarker(): PoseLandmarker {
        val baseOptions = BaseOptions.builder()
            .setModelAssetPath(POSE_MODEL_ASSET_PATH)
            .build()
        val options = PoseLandmarker.PoseLandmarkerOptions.builder()
            .setBaseOptions(baseOptions)
            .setRunningMode(RunningMode.VIDEO)
            .setNumPoses(1)
            .setMinPoseDetectionConfidence(0.5f)
            .setMinPosePresenceConfidence(0.5f)
            .setMinTrackingConfidence(0.5f)
            .build()
        return PoseLandmarker.createFromOptions(this, options)
    }

    private fun startCameraIfNeeded() {
        if (cameraStarted) {
            return
        }

        val cameraProviderFuture = ProcessCameraProvider.getInstance(this)
        cameraProviderFuture.addListener({
            try {
                val provider = cameraProviderFuture.get()
                bindCameraUseCases(provider)
            } catch (error: Exception) {
                reportError("相机启动失败：${error.localizedMessage ?: "unknown"}")
            }
        }, ContextCompat.getMainExecutor(this))
    }

    private fun bindCameraUseCases(provider: ProcessCameraProvider) {
        provider.unbindAll()

        val preview = androidx.camera.core.Preview.Builder().build().apply {
            setSurfaceProvider(previewView.surfaceProvider)
        }

        val analysis = ImageAnalysis.Builder()
            .setTargetResolution(Size(1280, 720))
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
            .build()

        analysis.setAnalyzer(cameraExecutor) { imageProxy ->
            analyzeFrame(imageProxy)
        }

        provider.bindToLifecycle(
            this,
            CameraSelector.DEFAULT_FRONT_CAMERA,
            preview,
            analysis
        )

        cameraProvider = provider
        cameraStarted = true
        updateStatus("相机已就绪")
        gestureLabel.text = "请展示手部"
        poseLabel.text = "请展示动作"
        HandGestureSdkPlugin.publishEvent(
            type = "ready",
            message = "相机已就绪"
        )
    }

    private fun analyzeFrame(imageProxy: ImageProxy) {
        if (!processingFrame.compareAndSet(false, true)) {
            imageProxy.close()
            return
        }

        val bitmap = try {
            imageProxyToBitmap(imageProxy)
        } catch (error: Exception) {
            processingFrame.set(false)
            imageProxy.close()
            reportError("图像转换失败：${error.localizedMessage ?: "unknown"}")
            return
        }

        val rotatedBitmap = rotateBitmap(bitmap, imageProxy.imageInfo.rotationDegrees)
        val timestampMs = nextTimestampMs()
        val mpImage = BitmapImageBuilder(rotatedBitmap).build()
        imageProxy.close()

        modelExecutor.execute {
            try {
                handLandmarker?.detectForVideo(mpImage, timestampMs)?.let { result ->
                    handleHandResult(result)
                }
                poseLandmarker?.detectForVideo(mpImage, timestampMs)?.let { result ->
                    handlePoseResult(result)
                }
            } catch (error: Exception) {
                reportError("识别失败：${error.localizedMessage ?: "unknown"}")
            } finally {
                mpImage.close()
                if (rotatedBitmap !== bitmap) {
                    rotatedBitmap.recycle()
                }
                bitmap.recycle()
                processingFrame.set(false)
            }
        }
    }

    private fun nextTimestampMs(): Long {
        val now = SystemClock.uptimeMillis()
        val next = if (now <= lastTimestampMs) {
            lastTimestampMs + 1
        } else {
            now
        }
        lastTimestampMs = next
        return next
    }

    private fun rotateBitmap(source: Bitmap, rotationDegrees: Int): Bitmap {
        if (rotationDegrees == 0) {
            return source
        }
        val matrix = Matrix().apply {
            postRotate(rotationDegrees.toFloat())
        }
        return Bitmap.createBitmap(source, 0, 0, source.width, source.height, matrix, true)
    }

    private fun imageProxyToBitmap(imageProxy: ImageProxy): Bitmap {
        val plane = imageProxy.planes.firstOrNull()
            ?: throw IllegalStateException("No image plane available")
        val bitmap = Bitmap.createBitmap(imageProxy.width, imageProxy.height, Bitmap.Config.ARGB_8888)
        val buffer = plane.buffer
        buffer.rewind()
        bitmap.copyPixelsFromBuffer(buffer)
        return bitmap
    }

    private fun handleHandResult(result: HandLandmarkerResult) {
        val landmarks = result.landmarks().firstOrNull()
        if (landmarks.isNullOrEmpty()) {
            updateStatus("未检测到手部")
            runOnUiThread {
                skeletonOverlayView.updateHandLandmarks(emptyList())
            }
            return
        }

        val handedness = result.handedness().firstOrNull()?.firstOrNull()
        val gesture = classifyHandGesture(landmarks)
        val metrics = buildHandMetrics(landmarks, handedness)
        val confidence = handedness?.score()?.toDouble() ?: metrics["confidence"] as? Double ?: 0.85

        runOnUiThread {
            gestureLabel.text = gesture
            skeletonOverlayView.updateHandLandmarks(toPointList(landmarks))
        }

        updateStatus("检测到${handedness?.categoryName() ?: "手"}")
        HandGestureSdkPlugin.publishEvent(
            type = "gesture",
            message = gesture,
            gesture = gesture,
            confidence = confidence,
            metrics = metrics
        )
    }

    private fun handlePoseResult(result: PoseLandmarkerResult) {
        val landmarks = result.landmarks().firstOrNull()
        if (landmarks.isNullOrEmpty()) {
            runOnUiThread {
                skeletonOverlayView.updatePoseLandmarks(emptyList())
            }
            return
        }

        val pose = classifyPose(landmarks)
        val metrics = buildPoseMetrics(landmarks)
        val confidence = metrics["confidence"] as? Double ?: 0.8

        runOnUiThread {
            poseLabel.text = pose
            skeletonOverlayView.updatePoseLandmarks(toPointList(landmarks))
        }

        HandGestureSdkPlugin.publishEvent(
            type = "pose",
            message = pose,
            pose = pose,
            confidence = confidence,
            metrics = metrics
        )
    }

    private fun classifyHandGesture(landmarks: List<NormalizedLandmark>): String {
        if (landmarks.size < 21) {
            return "未知"
        }

        val indexExtended = landmarks[8].y() < landmarks[6].y()
        val middleExtended = landmarks[12].y() < landmarks[10].y()
        val ringExtended = landmarks[16].y() < landmarks[14].y()
        val pinkyExtended = landmarks[20].y() < landmarks[18].y()
        val thumbExtended = landmarks[4].x() > landmarks[3].x()

        val extendedCount = listOf(indexExtended, middleExtended, ringExtended, pinkyExtended)
            .count { it }
        val curledCount = 4 - extendedCount

        return when {
            extendedCount == 4 -> "张开手掌"
            curledCount == 4 -> "握拳"
            indexExtended && middleExtended && !ringExtended && !pinkyExtended -> "胜利"
            indexExtended && !middleExtended && !ringExtended && !pinkyExtended -> "指向"
            thumbExtended && curledCount >= 3 -> "点赞"
            else -> "未知"
        }
    }

    private fun buildHandMetrics(
        landmarks: List<NormalizedLandmark>,
        handedness: Category?
    ): Map<String, Any> {
        val xs = landmarks.map { it.x().toDouble() }
        val ys = landmarks.map { it.y().toDouble() }
        val minX = xs.minOrNull() ?: 0.0
        val maxX = xs.maxOrNull() ?: 0.0
        val minY = ys.minOrNull() ?: 0.0
        val maxY = ys.maxOrNull() ?: 0.0
        val width = maxX - minX
        val height = maxY - minY

        return mapOf(
            "handArea" to width * height,
            "handCenterX" to (minX + maxX) / 2.0,
            "handCenterY" to (minY + maxY) / 2.0,
            "bboxWidth" to width,
            "bboxHeight" to height,
            "handedness" to (handedness?.categoryName() ?: "unknown"),
            "confidence" to (handedness?.score()?.toDouble() ?: 0.85)
        )
    }

    private fun classifyPose(landmarks: List<NormalizedLandmark>): String {
        if (landmarks.size <= 28) {
            return "未知"
        }

        val leftKnee = angle(landmarks[23], landmarks[25], landmarks[27])
        val rightKnee = angle(landmarks[24], landmarks[26], landmarks[28])

        return when {
            leftKnee < 140.0 && rightKnee < 140.0 -> "蹲下"
            leftKnee > 160.0 && rightKnee > 160.0 -> "站起"
            else -> "未知"
        }
    }

    private fun buildPoseMetrics(landmarks: List<NormalizedLandmark>): Map<String, Any> {
        if (landmarks.size <= 28) {
            return mapOf("confidence" to 0.5)
        }

        val leftKnee = angle(landmarks[23], landmarks[25], landmarks[27])
        val rightKnee = angle(landmarks[24], landmarks[26], landmarks[28])
        val leftHip = angle(landmarks[11], landmarks[23], landmarks[25])
        val rightHip = angle(landmarks[12], landmarks[24], landmarks[26])

        return mapOf(
            "leftKneeAngle" to leftKnee,
            "rightKneeAngle" to rightKnee,
            "leftHipAngle" to leftHip,
            "rightHipAngle" to rightHip,
            "confidence" to 0.8
        )
    }

    private fun angle(
        a: NormalizedLandmark,
        b: NormalizedLandmark,
        c: NormalizedLandmark
    ): Double {
        val abx = (a.x() - b.x()).toDouble()
        val aby = (a.y() - b.y()).toDouble()
        val cbx = (c.x() - b.x()).toDouble()
        val cby = (c.y() - b.y()).toDouble()

        val dot = abx * cbx + aby * cby
        val magnitude = kotlin.math.sqrt((abx * abx + aby * aby) * (cbx * cbx + cby * cby))
        if (magnitude <= 0.0) {
            return 0.0
        }

        val cosine = (dot / magnitude).coerceIn(-1.0, 1.0)
        return Math.acos(cosine) * 180.0 / Math.PI
    }

    private fun updateStatus(message: String) {
        if (lastStatusMessage == message) {
            return
        }
        lastStatusMessage = message
        runOnUiThread {
            statusLabel.text = message
        }
        HandGestureSdkPlugin.publishEvent(
            type = "status",
            message = message
        )
    }

    private fun reportError(message: String) {
        updateStatus(message)
        HandGestureSdkPlugin.publishEvent(
            type = "error",
            message = message
        )
    }

    private fun toPointList(landmarks: List<NormalizedLandmark>): List<PointF> {
        return landmarks.map { landmark ->
            PointF(landmark.x(), landmark.y())
        }
    }

    companion object {
        private const val HAND_MODEL_ASSET_PATH = "models/hand_landmarker.task"
        private const val POSE_MODEL_ASSET_PATH = "models/pose_landmarker_lite.task"
    }
}
