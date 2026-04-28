package com.xinzhang.voice_control_sdk

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.content.ContextCompat

internal class VoiceListeningService : Service() {
    private val handler = Handler(Looper.getMainLooper())

    private var audioRecord: AudioRecord? = null
    private var captureThread: Thread? = null
    private var listening = false
    private var currentConfig = VoiceConfig()

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        ensureNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopListeningInternal("stopped by user")
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_START, null -> {
                currentConfig = VoiceConfig.fromBundle(intent?.extras)
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
                    stopSelf()
                    return START_NOT_STICKY
                }
                listening = true
                startForegroundWithState("starting", "正在启动麦克风采集")
                startCapture()
                return START_STICKY
            }
            else -> return START_NOT_STICKY
        }
    }

    override fun onDestroy() {
        stopListeningInternal("service destroyed")
        super.onDestroy()
    }

    private fun hasAudioPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.RECORD_AUDIO,
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun startCapture() {
        handler.post {
            if (!listening) {
                return@post
            }
            if (audioRecord != null) {
                return@post
            }

            val sampleRate = currentConfig.sampleRate
            val minBufferSize = AudioRecord.getMinBufferSize(
                sampleRate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
            )
            if (minBufferSize <= 0) {
                VoiceEventHub.emitError(
                    code = "audio_capture_failed",
                    message = "Failed to query AudioRecord buffer size: $minBufferSize",
                )
                stopListeningInternal("audio buffer size error")
                stopSelf()
                return@post
            }

            val record = createAudioRecord(sampleRate, minBufferSize)
            audioRecord = record
            try {
                record.startRecording()
            } catch (error: Exception) {
                VoiceEventHub.emitError(
                    code = "audio_capture_failed",
                    message = error.message ?: error.toString(),
                )
                stopListeningInternal("audio record start error")
                stopSelf()
                return@post
            }

            VoiceEventHub.emitState(
                state = "listening",
                message = "正在采集音频",
                listening = true,
                activeListening = false,
            )

            val readBuffer = ShortArray(maxOf(minBufferSize / 2, sampleRate / 10))
            captureThread = Thread {
                captureLoop(record, readBuffer, sampleRate)
            }.also {
                it.name = "VoiceListeningService"
                it.start()
            }
        }
    }

    private fun captureLoop(record: AudioRecord, readBuffer: ShortArray, sampleRate: Int) {
        while (listening) {
            val read = try {
                record.read(readBuffer, 0, readBuffer.size)
            } catch (error: Exception) {
                VoiceEventHub.emitError(
                    code = "audio_capture_failed",
                    message = error.message ?: error.toString(),
                )
                break
            }

            if (read > 0) {
                VoiceEventHub.emitAudio(
                    pcm16le = shortsToBytes(readBuffer, read),
                    sampleRate = sampleRate,
                )
                continue
            }

            if (read == AudioRecord.ERROR_INVALID_OPERATION ||
                read == AudioRecord.ERROR_BAD_VALUE ||
                read == AudioRecord.ERROR_DEAD_OBJECT
            ) {
                VoiceEventHub.emitError(
                    code = "audio_stream_error",
                    message = "AudioRecord read failed: $read",
                )
                break
            }
        }

        stopListeningInternal("audio capture stopped")
        stopSelf()
    }

    private fun createAudioRecord(sampleRate: Int, minBufferSize: Int): AudioRecord {
        val bufferSize = maxOf(minBufferSize, sampleRate * 2 / 4)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            AudioRecord.Builder()
                .setAudioSource(MediaRecorder.AudioSource.VOICE_RECOGNITION)
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(sampleRate)
                        .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                        .build(),
                )
                .setBufferSizeInBytes(bufferSize)
                .build()
        } else {
            @Suppress("DEPRECATION")
            AudioRecord(
                MediaRecorder.AudioSource.VOICE_RECOGNITION,
                sampleRate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                bufferSize,
            )
        }
    }

    private fun shortsToBytes(samples: ShortArray, count: Int): ByteArray {
        val bytes = ByteArray(count * 2)
        var index = 0
        for (i in 0 until count) {
            val value = samples[i].toInt()
            bytes[index++] = (value and 0xff).toByte()
            bytes[index++] = ((value shr 8) and 0xff).toByte()
        }
        return bytes
    }

    private fun stopListeningInternal(reason: String) {
        listening = false
        try {
            audioRecord?.stop()
        } catch (_: Exception) {
            // Ignore teardown errors.
        }
        try {
            audioRecord?.release()
        } catch (_: Exception) {
            // Ignore teardown errors.
        }
        audioRecord = null
        captureThread = null
        stopForegroundCompat()
        VoiceEventHub.emitState(
            state = "stopped",
            message = reason,
            listening = false,
            activeListening = false,
        )
    }

    private fun stopForegroundCompat() {
        try {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } catch (_: Exception) {
            try {
                stopForeground(true)
            } catch (_: Exception) {
                // Ignore.
            }
        }
    }

    private fun startForegroundWithState(state: String, message: String) {
        VoiceEventHub.emitState(
            state = state,
            message = message,
            listening = true,
            activeListening = false,
        )
        val notification = buildNotification(message)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun buildNotification(contentText: String): Notification {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, NOTIFICATION_CHANNEL_ID)
                .setContentTitle("Robot voice control")
                .setContentText(contentText)
                .setSmallIcon(android.R.drawable.ic_btn_speak_now)
                .setOngoing(true)
                .build()
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
                .setContentTitle("Robot voice control")
                .setContentText(contentText)
                .setSmallIcon(android.R.drawable.ic_btn_speak_now)
                .setOngoing(true)
                .build()
        }
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            NOTIFICATION_CHANNEL_ID,
            "Robot Voice Control",
            NotificationManager.IMPORTANCE_LOW,
        )
        manager.createNotificationChannel(channel)
    }

    companion object {
        const val ACTION_START = "com.xinzhang.voice_control_sdk.START"
        const val ACTION_STOP = "com.xinzhang.voice_control_sdk.STOP"

        private const val NOTIFICATION_CHANNEL_ID = "voice_control_sdk"
        private const val NOTIFICATION_ID = 22137
    }
}
