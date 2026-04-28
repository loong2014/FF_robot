package com.xinzhang.voice_control_sdk

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

class VoiceControlSdkPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {
    private lateinit var applicationContext: Context
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL_NAME)
        methodChannel.setMethodCallHandler(this)

        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL_NAME)
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        VoiceEventHub.setSink(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getPlatformVersion" -> result.success("Android ${Build.VERSION.RELEASE}")
            "ensurePermissions" -> ensurePermissions(result)
            "startListening" -> {
                startVoiceService(call.arguments)
                result.success(null)
            }
            "stopListening" -> {
                stopVoiceService()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        VoiceEventHub.setSink(events)
    }

    override fun onCancel(arguments: Any?) {
        VoiceEventHub.setSink(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != PERMISSION_REQUEST_CODE) {
            return false
        }

        val granted = requiredPermissions().all { permission ->
            ContextCompat.checkSelfPermission(
                applicationContext,
                permission,
            ) == PackageManager.PERMISSION_GRANTED
        }
        pendingPermissionResult?.success(granted)
        pendingPermissionResult = null
        if (!granted) {
            VoiceEventHub.emitError(
                code = "microphone_permission_denied",
                message = "Voice permissions are not granted",
            )
        }
        return true
    }

    private fun ensurePermissions(result: MethodChannel.Result) {
        val missingPermissions = requiredPermissions().filter { permission ->
            ContextCompat.checkSelfPermission(
                applicationContext,
                permission,
            ) != PackageManager.PERMISSION_GRANTED
        }
        if (missingPermissions.isEmpty()) {
            result.success(true)
            return
        }

        val currentActivity = activity
        if (currentActivity == null) {
            VoiceEventHub.emitError(
                code = "microphone_permission_denied",
                message = "No foreground activity is available to request voice permissions",
            )
            result.success(false)
            return
        }

        if (pendingPermissionResult != null) {
            result.error(
                "permission_request_active",
                "A voice permission request is already active",
                null,
            )
            return
        }

        pendingPermissionResult = result
        ActivityCompat.requestPermissions(
            currentActivity,
            missingPermissions.toTypedArray(),
            PERMISSION_REQUEST_CODE,
        )
    }

    private fun startVoiceService(arguments: Any?) {
        if (!hasAudioPermission()) {
            VoiceEventHub.emitError(
                code = "microphone_permission_denied",
                message = "Microphone permission is not granted",
            )
            VoiceEventHub.emitState(
                state = "error",
                message = "麦克风权限未开启",
                listening = false,
                activeListening = false,
            )
            return
        }

        val config = VoiceConfig.fromArguments(arguments)
        val intent = Intent(applicationContext, VoiceListeningService::class.java).apply {
            action = VoiceListeningService.ACTION_START
            putExtra("sampleRate", config.sampleRate)
            putExtra("wakeWord", config.wakeWord)
            putExtra("sensitivity", config.sensitivity)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            applicationContext.startForegroundService(intent)
        } else {
            applicationContext.startService(intent)
        }
    }

    private fun stopVoiceService() {
        val intent = Intent(applicationContext, VoiceListeningService::class.java).apply {
            action = VoiceListeningService.ACTION_STOP
        }
        applicationContext.startService(intent)
    }

    private fun hasAudioPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            applicationContext,
            Manifest.permission.RECORD_AUDIO,
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun requiredPermissions(): List<String> {
        val permissions = mutableListOf(Manifest.permission.RECORD_AUDIO)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            permissions.add(Manifest.permission.POST_NOTIFICATIONS)
        }
        return permissions
    }

    companion object {
        private const val METHOD_CHANNEL_NAME = "voice_control_sdk"
        private const val EVENT_CHANNEL_NAME = "voice_control_sdk/events"
        private const val PERMISSION_REQUEST_CODE = 7421
    }
}
