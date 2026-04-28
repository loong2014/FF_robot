package com.xinzhang.hand_gesture_sdk

import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class HandGestureSdkPlugin : FlutterPlugin, MethodCallHandler, EventChannel.StreamHandler, ActivityAware {

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var activity: Activity? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL_NAME)
        methodChannel.setMethodCallHandler(this)

        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL_NAME)
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getPlatformVersion" -> result.success("Android ${android.os.Build.VERSION.RELEASE}")
            "startRecognition" -> {
                val currentActivity = activity
                if (currentActivity == null) {
                    result.error("no_activity", "Flutter plugin is not attached to an Activity.", null)
                    return
                }
                currentActivity.startActivity(Intent(currentActivity, GestureActivity::class.java))
                result.success(null)
            }
            "stopRecognition" -> {
                GestureActivityRegistry.currentActivity?.finish()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    companion object {
        private const val METHOD_CHANNEL_NAME = "hand_gesture_sdk"
        private const val EVENT_CHANNEL_NAME = "hand_gesture_sdk/events"

        @Volatile
        private var eventSink: EventChannel.EventSink? = null

        private val mainHandler = Handler(Looper.getMainLooper())

        fun publishEvent(
            type: String,
            message: String,
            gesture: String? = null,
            pose: String? = null,
            confidence: Double? = null,
            metrics: Map<String, Any>? = null
        ) {
            val payload = mutableMapOf<String, Any>(
                "type" to type,
                "message" to message
            )
            if (!gesture.isNullOrBlank()) {
                payload["gesture"] = gesture
            }
            if (!pose.isNullOrBlank()) {
                payload["pose"] = pose
            }
            if (confidence != null) {
                payload["confidence"] = confidence
            }
            if (!metrics.isNullOrEmpty()) {
                payload["metrics"] = metrics
            }
            mainHandler.post {
                eventSink?.success(payload)
            }
        }
    }
}
