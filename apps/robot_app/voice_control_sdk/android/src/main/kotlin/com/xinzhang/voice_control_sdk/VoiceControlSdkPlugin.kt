package com.xinzhang.voice_control_sdk

import android.content.Context
import android.content.Intent
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class VoiceControlSdkPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {
    private lateinit var applicationContext: Context
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel

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

    private fun startVoiceService(arguments: Any?) {
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

    companion object {
        private const val METHOD_CHANNEL_NAME = "voice_control_sdk"
        private const val EVENT_CHANNEL_NAME = "voice_control_sdk/events"
    }
}
