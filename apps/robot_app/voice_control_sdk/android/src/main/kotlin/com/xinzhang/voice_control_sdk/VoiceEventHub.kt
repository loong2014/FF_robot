package com.xinzhang.voice_control_sdk

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

internal object VoiceEventHub {
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var eventSink: EventChannel.EventSink? = null

    fun setSink(sink: EventChannel.EventSink?) {
        eventSink = sink
    }

    fun emit(event: Map<String, Any?>) {
        val payload = HashMap<String, Any?>(event)
        mainHandler.post {
            eventSink?.success(payload)
        }
    }

    fun emitState(
        state: String,
        message: String,
        listening: Boolean,
        activeListening: Boolean,
        source: String = "android",
    ) {
        emit(
            mapOf(
                "type" to "state",
                "state" to state,
                "message" to message,
                "listening" to listening,
                "activeListening" to activeListening,
                "engine" to "sherpa",
                "source" to source,
                "timestampMs" to System.currentTimeMillis(),
            )
        )
    }

    fun emitAudio(
        pcm16le: ByteArray,
        sampleRate: Int,
        source: String = "android",
    ) {
        emit(
            mapOf(
                "type" to "audio",
                "format" to "pcm16le",
                "samples" to pcm16le,
                "sampleRate" to sampleRate,
                "channels" to 1,
                "sampleCount" to pcm16le.size / 2,
                "source" to source,
                "timestampMs" to System.currentTimeMillis(),
            )
        )
    }

    fun emitError(
        code: String,
        message: String,
        source: String = "android",
    ) {
        emit(
            mapOf(
                "type" to "error",
                "code" to code,
                "message" to message,
                "source" to source,
                "timestampMs" to System.currentTimeMillis(),
            )
        )
    }

    fun emitTelemetry(
        message: String,
        source: String = "android",
    ) {
        emit(
            mapOf(
                "type" to "telemetry",
                "message" to message,
                "source" to source,
                "timestampMs" to System.currentTimeMillis(),
            )
        )
    }
}
