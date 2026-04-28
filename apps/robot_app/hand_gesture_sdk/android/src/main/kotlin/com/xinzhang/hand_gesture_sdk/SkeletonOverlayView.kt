package com.xinzhang.hand_gesture_sdk

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PointF
import android.graphics.RectF
import android.util.AttributeSet
import android.view.View

internal class SkeletonOverlayView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : View(context, attrs) {

    private val handConnectionPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#FFB54A")
        style = Paint.Style.STROKE
        strokeWidth = 6f
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }

    private val poseConnectionPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#46D7FF")
        style = Paint.Style.STROKE
        strokeWidth = 5f
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }

    private val handNodePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#FFE9A6")
        style = Paint.Style.FILL
    }

    private val poseNodePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#E6FFFF")
        style = Paint.Style.FILL
    }

    private val handNodeStrokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#7F4C00")
        style = Paint.Style.STROKE
        strokeWidth = 3f
    }

    private val poseNodeStrokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#00596F")
        style = Paint.Style.STROKE
        strokeWidth = 2f
    }

    private val handLandmarks = MutableList(21) { PointF() }
    private val poseLandmarks = MutableList(33) { PointF() }

    private var handVisible = false
    private var poseVisible = false
    private var mirrorX = true

    fun updateHandLandmarks(points: List<PointF>?) {
        handVisible = !points.isNullOrEmpty()
        if (points != null) {
            handLandmarks.clear()
            handLandmarks.addAll(points)
        }
        postInvalidateOnAnimation()
    }

    fun updatePoseLandmarks(points: List<PointF>?) {
        poseVisible = !points.isNullOrEmpty()
        if (points != null) {
            poseLandmarks.clear()
            poseLandmarks.addAll(points)
        }
        postInvalidateOnAnimation()
    }

    fun clear() {
        handVisible = false
        poseVisible = false
        postInvalidateOnAnimation()
    }

    fun setMirrorX(enabled: Boolean) {
        mirrorX = enabled
        postInvalidateOnAnimation()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (handVisible) {
            drawConnections(canvas, handLandmarks, HAND_CONNECTIONS, handConnectionPaint)
            drawLandmarks(canvas, handLandmarks, handNodePaint, handNodeStrokePaint, 12f)
        }
        if (poseVisible) {
            drawConnections(canvas, poseLandmarks, POSE_CONNECTIONS, poseConnectionPaint)
            drawLandmarks(canvas, poseLandmarks, poseNodePaint, poseNodeStrokePaint, 9f)
        }
    }

    private fun drawConnections(
        canvas: Canvas,
        landmarks: List<PointF>,
        connections: Array<IntArray>,
        paint: Paint
    ) {
        connections.forEach { connection ->
            if (connection.size < 2) {
                return@forEach
            }
            val start = connection[0]
            val end = connection[1]
            if (start >= landmarks.size || end >= landmarks.size) {
                return@forEach
            }
            val startPoint = mapPoint(landmarks[start])
            val endPoint = mapPoint(landmarks[end])
            canvas.drawLine(startPoint.x, startPoint.y, endPoint.x, endPoint.y, paint)
        }
    }

    private fun drawLandmarks(
        canvas: Canvas,
        landmarks: List<PointF>,
        fillPaint: Paint,
        strokePaint: Paint,
        radius: Float
    ) {
        landmarks.forEach { landmark ->
            val point = mapPoint(landmark)
            canvas.drawCircle(point.x, point.y, radius, strokePaint)
            canvas.drawCircle(point.x, point.y, radius - 2f, fillPaint)
        }
    }

    private fun mapPoint(point: PointF): PointF {
        val x = if (mirrorX) width * (1f - point.x) else width * point.x
        val y = height * point.y
        return PointF(x, y)
    }

    companion object {
        private val HAND_CONNECTIONS = arrayOf(
            intArrayOf(0, 1),
            intArrayOf(1, 2),
            intArrayOf(2, 3),
            intArrayOf(3, 4),
            intArrayOf(0, 5),
            intArrayOf(5, 6),
            intArrayOf(6, 7),
            intArrayOf(7, 8),
            intArrayOf(5, 9),
            intArrayOf(9, 10),
            intArrayOf(10, 11),
            intArrayOf(11, 12),
            intArrayOf(9, 13),
            intArrayOf(13, 14),
            intArrayOf(14, 15),
            intArrayOf(15, 16),
            intArrayOf(13, 17),
            intArrayOf(17, 18),
            intArrayOf(18, 19),
            intArrayOf(19, 20),
            intArrayOf(0, 17)
        )

        private val POSE_CONNECTIONS = arrayOf(
            intArrayOf(0, 1),
            intArrayOf(1, 2),
            intArrayOf(2, 3),
            intArrayOf(3, 7),
            intArrayOf(0, 4),
            intArrayOf(4, 5),
            intArrayOf(5, 6),
            intArrayOf(6, 8),
            intArrayOf(9, 10),
            intArrayOf(11, 12),
            intArrayOf(11, 13),
            intArrayOf(13, 15),
            intArrayOf(15, 17),
            intArrayOf(15, 19),
            intArrayOf(15, 21),
            intArrayOf(17, 19),
            intArrayOf(12, 14),
            intArrayOf(14, 16),
            intArrayOf(16, 18),
            intArrayOf(16, 20),
            intArrayOf(16, 22),
            intArrayOf(18, 20),
            intArrayOf(11, 23),
            intArrayOf(12, 24),
            intArrayOf(23, 24),
            intArrayOf(23, 25),
            intArrayOf(25, 27),
            intArrayOf(27, 29),
            intArrayOf(29, 31),
            intArrayOf(24, 26),
            intArrayOf(26, 28),
            intArrayOf(28, 30),
            intArrayOf(30, 32),
            intArrayOf(27, 31),
            intArrayOf(28, 32)
        )
    }
}
