package com.xinzhang.voice_control_sdk

import android.os.Bundle

internal data class VoiceConfig(
    val sampleRate: Int = 16000,
    val wakeWord: String = "Lumi",
    val sensitivity: Double = 0.65,
) {
    companion object {
        private const val KEY_SAMPLE_RATE = "sampleRate"
        private const val KEY_WAKE_WORD = "wakeWord"
        private const val KEY_SENSITIVITY = "sensitivity"

        fun fromArguments(arguments: Any?): VoiceConfig {
            if (arguments !is Map<*, *>) {
                return VoiceConfig()
            }

            return VoiceConfig(
                sampleRate = readInt(arguments, KEY_SAMPLE_RATE, 16000),
                wakeWord = readString(arguments, KEY_WAKE_WORD, "Lumi"),
                sensitivity = readDouble(arguments, KEY_SENSITIVITY, 0.65),
            )
        }

        fun fromBundle(extras: Bundle?): VoiceConfig {
            if (extras == null) {
                return VoiceConfig()
            }
            return VoiceConfig(
                sampleRate = if (extras.containsKey(KEY_SAMPLE_RATE)) {
                    extras.getInt(KEY_SAMPLE_RATE)
                } else {
                    16000
                },
                wakeWord = extras.getString(KEY_WAKE_WORD) ?: "Lumi",
                sensitivity = if (extras.containsKey(KEY_SENSITIVITY)) {
                    extras.getDouble(KEY_SENSITIVITY)
                } else {
                    0.65
                },
            )
        }

        private fun readString(map: Map<*, *>, key: String, fallback: String): String {
            return map[key]?.toString()?.takeIf { it.isNotBlank() } ?: fallback
        }

        private fun readDouble(map: Map<*, *>, key: String, fallback: Double): Double {
            val value = map[key]
            return when (value) {
                is Double -> value
                is Float -> value.toDouble()
                is Number -> value.toDouble()
                is String -> value.toDoubleOrNull() ?: fallback
                else -> fallback
            }
        }

        private fun readInt(map: Map<*, *>, key: String, fallback: Int): Int {
            val value = map[key]
            return when (value) {
                is Int -> value
                is Number -> value.toInt()
                is String -> value.toIntOrNull() ?: fallback
                else -> fallback
            }
        }
    }
}
